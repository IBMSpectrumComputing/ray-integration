from os import popen
import ray
import time
import os

#connect to head node
head_node=str(os.environ["head_node"])
port=str(os.environ["port"])
print(head_node,port)
ray.init(address=head_node+":"+port)

#@ray.remote(memory=5 * 1024 * 1024*1024)
@ray.remote
def f():
    time.sleep(30)
    return ray.get_runtime_context().node_id.hex()

#run function for n times and check the node values
print("working on tasks..")
results = set(ray.get([f.remote() for x in range(150)]))
print(results)
print("Done processing shutting down ray cluster")
ray.shutdown()
