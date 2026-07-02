cat > ~/platform-restore.sh <<'EOF'
#!/bin/bash
set -e

ask() {
  echo
  read -rp "Continue? [y=continue / s=skip / q=quit]: " ans
  case "$ans" in
    y|Y|"") return 0 ;;
    s|S) return 1 ;;
    q|Q) echo "Stopped by user."; exit 0 ;;
    *) echo "Please answer y, s, or q."; ask ;;
  esac
}

section() {
  echo
  echo "======================================="
  echo "$1"
  echo "======================================="
}

section "1. Start MicroK8s"
if ask; then
  microk8s start
  microk8s status --wait-ready
fi

section "2. Verify hostname and node identity"
if ask; then
  echo "Hostname:"
  hostname
  echo
  microk8s kubectl get nodes
fi

section "3. Remove stale old node 'joach' if present"
if ask; then
  if microk8s kubectl get node joach >/dev/null 2>&1; then
    microk8s kubectl delete node joach || true
  else
    echo "No stale node 'joach' found."
  fi
fi

section "4. Refresh MLflow MinIO credentials"
if ask; then
  CREDS=$(juju run mlflow-server/0 get-minio-credentials)

  ACCESS_KEY=$(echo "$CREDS" | awk '/access-key:/ {print $2}')
  SECRET_KEY=$(echo "$CREDS" | awk '/secret-access-key:/ {print $2}')

  echo "Access key: $ACCESS_KEY"
  echo "Secret key refreshed."
fi

section "5. Patch MLflow artifact secret"
if ask; then
  microk8s kubectl patch secret mlflow-server-minio-artifact \
    -n admin \
    --type merge \
    -p "{\"stringData\":{\"AWS_ACCESS_KEY_ID\":\"$ACCESS_KEY\",\"AWS_SECRET_ACCESS_KEY\":\"$SECRET_KEY\",\"accesskey\":\"$ACCESS_KEY\",\"secretkey\":\"$SECRET_KEY\"}}"
fi

section "6. Patch KServe S3 secret"
if ask; then
  microk8s kubectl patch secret kserve-controller-s3 \
    -n admin \
    --type merge \
    -p "{\"stringData\":{\"AWS_ACCESS_KEY_ID\":\"$ACCESS_KEY\",\"AWS_SECRET_ACCESS_KEY\":\"$SECRET_KEY\",\"accesskey\":\"$ACCESS_KEY\",\"secretkey\":\"$SECRET_KEY\",\"AWS_ENDPOINT_URL\":\"http://mlflow-minio.kubeflow:9000\",\"AWS_REGION\":\"us-east-1\",\"S3_ENDPOINT\":\"http://mlflow-minio.kubeflow:9000\"}}"
fi

section "7. Verify Ollama service"
if ask; then
  if systemctl is-active --quiet ollama; then
    echo "Ollama is already running."
  else
    echo "Starting Ollama..."
    sudo systemctl start ollama
  fi

  systemctl --no-pager --lines=5 status ollama || true
fi

section "8. Verify Ollama API"
if ask; then
  curl -s http://localhost:11434/api/version
  echo
  echo "Ollama API reachable."
fi

section "9. List Ollama models"
if ask; then
  ollama list || true
fi

section "10. Verify Ollama listening address"
if ask; then
  sudo ss -ltnp | grep 11434 || true
fi

section "11. Recreate notebook pod"
if ask; then
  if microk8s kubectl get pod -n admin testkubgpu1-0 >/dev/null 2>&1; then
    microk8s kubectl delete pod -n admin testkubgpu1-0
    echo "Notebook pod deleted. Kubeflow will recreate it."
  else
    echo "Notebook pod testkubgpu1-0 not found."
  fi
fi

section "12. Run Kubeflow health check"
if ask; then
  ~/kubeflow-healthcheck.sh
fi

section "13. Platform summary"
echo
echo "======================================="
echo " AI PLATFORM RESTORE FINISHED"
echo "======================================="
echo "Check manually:"
echo "  1. microk8s kubectl get nodes"
echo "  2. microk8s kubectl get pods -A | grep -v Running"
echo "  3. ollama list"
echo "  4. curl http://localhost:11434/api/version"
echo "  5. Open Kubeflow notebook"
echo "  6. In notebook: import torch; torch.cuda.is_available()"
echo "  7. In agentic kernel: test LangChain + Ollama"
echo
echo "Platform restore completed."
EOF

chmod +x ~/platform-restore.sh
