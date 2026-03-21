#!/bin/bash
set -e

echo "Adding Helm repos..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo "Creating monitoring namespace..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo "Installing kube-prometheus-stack..."
helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword="admin123" \
  --set prometheus.prometheusSpec.retention="7d" \
  --set alertmanager.enabled=true \
  --timeout 10m

echo "Installing Loki stack..."
helm install loki-stack grafana/loki-stack \
  --namespace monitoring \
  --set promtail.enabled=true \
  --set loki.enabled=true \
  --set grafana.enabled=false

echo "Applying alert rules..."
kubectl apply -f alert-rules.yaml

echo "Done. Port forward Grafana with:"
echo "kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"
