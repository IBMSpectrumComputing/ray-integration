#!/bin/bash
#Run ray on LSF.
#Examples
# bsub -n 2 -R "span[ptile=1] rusage[mem=4GB]" -gpu "num=2" -o std.out%J -e std.out%J ray_launch_cluster.sh -n conda_env -c "workload args..."
#   Run a workload on two nodes. Each node has single core and 2 GPUs. Nodes are placed on separated hosts.
# bsub -n 4 -R "affinity[core(7,same=socket)]" -gpu "num=2/task" -o std.out%J -e std.out%J ray_launch_cluster.sh -n conda_env -c "workload args..."
#   Run a workload on 4 nodes. Each node has 7 cores and 2 GPUs.
#   "/task" for GPU option is necessary because multiple nodes may run on a same host. Otherwise 2 GPUs on a host will be shared by all nodes (tasks) on the host.
echo "LSB_MCPU_HOSTS=$LSB_MCPU_HOSTS"
echo "---- LSB_AFFINITY_HOSTFILE=$LSB_AFFINITY_HOSTFILE"
cat $LSB_AFFINITY_HOSTFILE
echo "---- End of LSB_AFFINITY_HOSTFILE"
echo "---- LSB_DJOB_HOSTFILE=$LSB_DJOB_HOSTFILE"
cat $LSB_DJOB_HOSTFILE
echo "---- End of LSB_DJOB_HOSTFILE"

# Use user specific temporary folder for multi-tenancy environment
export RAY_TMPDIR="/tmp/ray-$USER"
echo "RAY_TMPDIR=$RAY_TMPDIR"
mkdir -p $RAY_TMPDIR

#bias to selection of higher range ports
function getfreeport()
{
    CHECK="do while"
    while [[ ! -z $CHECK ]]; do
        port=$(( ( RANDOM % 40000 )  + 20000 ))
        CHECK=$(netstat -a | grep $port)
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
        echo "Adding host: $host"
        hosts+=($host)
done

echo "The host list is: ${hosts[@]}"

port=$(getfreeport)
echo "Head node will use port: $port"

export port

dashboard_port=$(getfreeport)
echo "Dashboard will use port: $dashboard_port"

# Compute number of cores allocated to hosts
# Format of each line in file $LSB_AFFINITY_HOSTFILE:
#   host_name core_id_list NUMA_node_id_list memory_policy
# core_id_list is comma separeted core IDs. e.g.
#   host1 1,2,3,4,5,6,7
#   host2 0,2,3,4,6,7,8
#   host2 19,21,22,23,24,26,27
#   host2 28,29,37,41,48,49,50
# First, count up number of cores for each line (slot), then sum up for same host.
declare -A associative
while read -a line
do
    host=${line[0]}
    num_cpu=`echo ${line[1]} | tr , ' ' | wc -w`
    ((associative[$host]+=$num_cpu))
done < $LSB_AFFINITY_HOSTFILE
for host in ${!associative[@]}; do
    echo host=$host cores=${associative[$host]}
done

#Assumption only one head node and more than one 
#workers will connect to head node

head_node=${hosts[0]}

export head_node

echo "Object store memory for the cluster is set to 4GB"

echo "Starting ray head node on: ${hosts[0]}"

if [ -z $object_store_mem ]
then
    echo "using default object store mem of 4GB make sure your cluster has mem greater than 4GB"
    object_store_mem=4000000000
else
    echo "The object store memory in bytes is: $object_store_mem"
fi

num_cpu_for_head=${associative[$head_node]}
# Number of GPUs available for each host is detected "ray start" command
command_launch="blaunch -z ${hosts[0]} ray start --head --port $port --dashboard-port $dashboard_port --num-cpus $num_cpu_for_head --object-store-memory $object_store_mem"

$command_launch &



sleep 20

command_check_up="ray status --address $head_node:$port"

while ! $command_check_up
do
    sleep 3
done



workers=("${hosts[@]:1}")

echo "adding the workers to head node: ${workers[*]}"
#run ray on worker nodes and connect to head
for host in "${workers[@]}"
do
    echo "starting worker on: $host and using master node: $head_node"

    sleep 10
    num_cpu=${associative[$host]}
    command_for_worker="blaunch -z $host ray  start --address $head_node:$port --num-cpus $num_cpu --object-store-memory $object_store_mem"
    
    
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
echo "Running user workload: $user_command"
$user_command


if [ $? != 0 ]; then
    echo "Failure: $?"
    exit $?
else
    echo "Done"
    echo "Shutting down the Job"
    bkill $LSB_JOBID
fi
