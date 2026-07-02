#!/bin/bash
set -e

echo "=== Starting MicroK8s ==="
microk8s start
microk8s status --wait-ready

echo
echo "=== Hostname / Node identity ==="
hostname
microk8s kubectl get nodes

echo
echo "=== Removing stale node if present ==="
if microk8s kubectl get node joach >/dev/null 2>&1; then
  microk8s kubectl delete node joach || true
fi

echo
echo "=== Refresh MLflow MinIO secret in admin namespace ==="
CREDS=$(juju run mlflow-server/0 get-minio-credentials)

ACCESS_KEY=$(echo "$CREDS" | awk '/access-key:/ {print $2}')
SECRET_KEY=$(echo "$CREDS" | awk '/secret-access-key:/ {print $2}')

echo "Access key: $ACCESS_KEY"
echo "Secret key refreshed."

microk8s kubectl patch secret mlflow-server-minio-artifact \
  -n admin \
  --type merge \
  -p "{\"stringData\":{\"AWS_ACCESS_KEY_ID\":\"$ACCESS_KEY\",\"AWS_SECRET_ACCESS_KEY\":\"$SECRET_KEY\",\"accesskey\":\"$ACCESS_KEY\",\"secretkey\":\"$SECRET_KEY\"}}"

microk8s kubectl patch secret kserve-controller-s3 \
  -n admin \
  --type merge \
  -p "{\"stringData\":{\"AWS_ACCESS_KEY_ID\":\"$ACCESS_KEY\",\"AWS_SECRET_ACCESS_KEY\":\"$SECRET_KEY\",\"accesskey\":\"$ACCESS_KEY\",\"secretkey\":\"$SECRET_KEY\"}}"

echo
echo "=== Recreate notebook pod to reload secrets ==="
if microk8s kubectl get pod -n admin testkubgpu1-0 >/dev/null 2>&1; then
  microk8s kubectl delete pod -n admin testkubgpu1-0
fi

echo
echo "=== Health check ==="
~/kubeflow-healthcheck.sh

echo
echo "Restore check finished."
echo "Open the notebook and verify:"
echo '  import os; print(os.getenv("AWS_SECRET_ACCESS_KEY"))'
