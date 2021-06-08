# ray-integration
Ray provides a simple, universal API for building distributed applications, read more about ray [here](https://docs.ray.io/en/master/index.html).  
Ray integration with LSF enables users to start up a Ray cluster on LSF and run DL workloads through that either in a batch or interactive mode.

# Configuring Conda 

- Before you begin make sure you have conda install on your machine, details about installing conda on linux machine is [here](https://docs.conda.io/projects/conda/en/latest/user-guide/install/linux.html).  
- For reference sample conda env yml is present [here](https://github.com/IBMSpectrumComputing/ray-integration/tree/main/sample_conda_env), to create sample conda env that will run GPU and CPU workloads run, it has mix of conda and pip dependencies:
  ```
  conda env create -f sample_conda_env/sample_ray_env.yml
  ```
- To test if you have ray installed with version number run:
   ```
    conda activate ray
    pip install -U ray
    ray --version
    ```
 # Running ray as interactive LSF job
 
 - Run the below bsub command to get multiple GPUs (i.e. 2 GPUs in this example) on multiple nodes (i.e. 2 hosts in this example) from LSF scheduler with 20GB hardlimit on memory 
    ```
    bsub -Is -M 20GB! -n 2 -R "span[ptile=1]" -gpu "num=2" bash
    ```
 - Sample workloads are present in sample_workload directory, sample_code_for_ray.py is CPU only workload and cifar_pytorch_example.py will work on CPU as well as GPU.
 - Start the script by running the following command:
    ```
    ./ray_launch_cluster.sh -c "python <full_path_of_sample_workload>/cifar_pytorch_example.py --use-gpu --num_epochs 5" -n "ray" -m 20000000000
    ```
    Where:  
        -c is the user command that needs to be scaled under ray  
        -n is the conda namespace that will be activate before the cluster is spawned  
        -m is object store memory size in bytes as required by ray  
 
 # Running ray as a batch job
 - Run the below command to run ray as batch job
    ```
      bsub -o std%J.out -e std%J.out -M 20GB! -n 2 -R "span[ptile=1]" -gpu "num=2"  ./ray_launch_cluster.sh -c "python <full_path_of_sample_workload>/cifar_pytorch_example.py " -n "ray" -m 20000000000
    ```
 # Acessing ray dashboard in interactive job mode:
 - Get ray head node and dashboard port, please find below log lines on the console
    ```
    Starting ray head node on:  ccc2-10
    The size of object store memory in bytes is:  20000000000
    2021-06-07 14:19:11,441 INFO services.py:1269 -- View the Ray dashboard at http://127.0.0.1:3752
    ```
    Where:  
        - head node name: ccc2-10  
        - dashboard port: 3752  
 - Run the below set of commands on the terminal to port forward dashboard from cluster to your local machine:
    ```
    export PORT=3752
    export HEAD_NODE=ccc2-10.sl.cloud.ibm.com
    ssh -L $PORT:localhost:$PORT -N -f -l <username> $HEAD_NODE
    ```
 - Access the dashboard at your laptop on:
    ```
      http://127.0.0.1:3752
    ```
        
