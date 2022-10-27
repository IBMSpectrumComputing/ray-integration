#!/bin/bash
#Run ray on LSF.
#eg:bsub -n 2 -R "span[ptile=1] rusage[mem=4GB]" -o std.out%J -e std.out%J bash -i ray_launch_cluster.sh

#bias to selection of higher range ports
function getfreeport()
{
    CHECK="do while"
    while [[ ! -z $CHECK ]]; do
        port=$(( ( RANDOM % 40000 )  + 20000 ))
        CHECK=$(sudo netstat -ap | grep $port)
    done
    echo $port
}

while getopts ":c:n:m:" option;do
    case "${option}" in
    c) c=${OPTARG}
        user_command=$c
    ;;
    n) n=${OPTARG}
        conda_env=$n
    ;;
    m) m=${OPTARG}
        object_store_mem=$m
    ;;
    *) echo "Did not supply the correct arguments"
    ;;
    esac
    done



#use bash -i to activate conda env when the script is launched
#or use the below syntax.
if [ -z "$conda_env" ]
then
    echo "No conda env provided, is ray installed?"
else

    eval "$(conda shell.bash hook)"
    conda activate $conda_env
fi


hosts=()
for host in `cat $LSB_DJOB_HOSTFILE | uniq`
do
        echo "Adding host: " $host
        hosts+=($host)
done

echo "The host list is: " "${hosts[@]}"

port=$(getfreeport)
echo "Head node will use port: " $port

export port

dashboard_port=$(getfreeport)
echo "Dashboard will use port: " $dashboard_port


echo "Num cpus per host is:" $LSB_MCPU_HOSTS
IFS=' ' read -r -a array <<< "$LSB_MCPU_HOSTS"
declare -A associative
i=0
len=${#array[@]}
while [ $i -lt $len ]
do
    key=${array[$i]}
    value=${array[$i+1]}
    associative[$key]+=$value
    i=$((i=i+2))
done

num_gpu=0
if [ -z "$CUDA_VISIBLE_DEVICES" ]
then
    num_gpu=0
else
    num_gpu=$CUDA_VISIBLE_DEVICES
fi

#Assumption only one head node and more than one 
#workers will connect to head node

head_node=${hosts[0]}

export head_node

echo "Object store memory for the cluster is set to 4GB"

echo "Starting ray head node on: " ${hosts[0]}

if [ -z $object_store_mem ]
then
    echo "using default object store mem of 4GB make sure your cluster has mem greater than 4GB"
    object_store_mem=4000000000
else
    echo "The object store memory in bytes is: " "$object_store_mem"
fi

num_cpu_for_head=${associative[$head_node]}

command_launch="blaunch -z ${hosts[0]} ray start --head --port $port --dashboard-port $dashboard_port --object-store-memory $object_store_mem"


$command_launch &



sleep 20

command_check_up="ray status --address $head_node:$port"

while ! $command_check_up
do
    sleep 3
done



workers=("${hosts[@]:1}")

echo "adding the workers to head node: " "${workers[*]}"
#run ray on worker nodes and connect to head
for host in "${workers[@]}"
do
    echo "starting worker on: " $host "and using master node: " $head_node

    sleep 10
    num_cpu=${associative[$host]}
    #command_for_worker="blaunch -z $host ray  start --address $head_node:$port --num-cpus $num_cpu --num-gpus $num_gpu --object-store-memory $object_store_mem"
    command_for_worker="blaunch -z $host ray  start --address $head_node:$port  --object-store-memory $object_store_mem"
    
    
    $command_for_worker &
    sleep 10
    command_check_up_worker="blaunch -z $host ray  status --address $head_node:$port"
    while ! $command_check_up_worker
    do
        sleep 3
    done
done

#Run workload
#eg of user workload python sample_code_for_ray.py
echo "Running user workload: " $user_command 
$user_command


if [ $? != 0 ]; then
    echo "Failure: " $?
    exit $?
else
    echo "Done"
    echo "Shutting down the Job"
    bkill $LSB_JOBID
fi
