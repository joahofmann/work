nvidia-smi
microk8s status
microk8s kubectl get nodes
microk8s kubectl describe node joachim | grep nvidia.com/gpu
microk8s kubectl get runtimeclass
microk8s kubectl get clusterpolicy
microk8s kubectl get pods -A | grep -v Running | grep -v Completed
juju status | grep -E 'mlflow|minio|jupyter|kfp|katib|kserve'
