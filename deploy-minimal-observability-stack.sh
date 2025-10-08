#!/bin/bash
set -e

echo "Combined Deployment: Step 1 + Step 2"
echo "====================================="
echo "This will deploy:"
echo "  - k3d cluster"
echo "  - OpenTelemetry Collector"
echo "  - Tempo (trace storage)"
echo ""

echo "Step 1: Base Infrastructure"
echo "============================"

echo "Creating k3d cluster..."
k3d cluster create mycluster --agents 1 --wait
echo "   ✅ Cluster ready"

echo "Adding helm repositories..."
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update >/dev/null
echo "   ✅ Repositories updated"

echo "Creating namespaces..."
kubectl create namespace observability 2>/dev/null || true
kubectl create namespace my-demo 2>/dev/null || true
echo "   ✅ Namespaces created"

echo ""
echo "Step 2: Deploy Observability Stack"
echo "==================================="

echo "Deploying Tempo..."
helm upgrade --install dev-tempo grafana/tempo \
  --version 1.18.2 --namespace observability \
  -f observability-stack-helm-values/tempo.yaml \
  --wait --timeout=5m
echo "   ✅ Tempo deployed"

echo "Deploying OpenTelemetry Collector (with Tempo export)..."
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --version 0.111.2 --namespace observability \
  -f observability-stack-helm-values/otel-collector-minimal.yaml \
  --wait --timeout=5m
echo "   ✅ OTel Collector deployed"

echo "Deploying Grafana (with Tempo datasource)..."
helm upgrade --install dev-grafana grafana/grafana \
  --version 9.0.0 --namespace observability \
  -f observability-stack-helm-values/grafana-minimal.yaml \
  --wait --timeout=5m
echo "   ✅ Grafana deployed"

echo ""
echo "Step 3: Port Forwarding"
echo "======================="

echo "Starting port-forwards..."
pkill -f "kubectl port-forward" 2>/dev/null || true

kubectl port-forward -n observability svc/dev-tempo 3100:3100 >/dev/null 2>&1 &
kubectl port-forward -n observability svc/dev-grafana 3000:80 >/dev/null 2>&1 &

sleep 3
echo "   ✅ Port-forwards started"

echo ""
echo "====================================="
echo "Deployment Complete!"
echo "====================================="
echo ""
echo "Services available:"
echo "  - Tempo API: http://localhost:3100"
echo "  - Grafana: http://localhost:3000 (admin/admin)"
echo ""
echo "Next steps:"
echo "  1. Deploy your apps: skaffold run"
echo "  2. Wait for CronJob to run (every minute)"
echo "  3. Open Grafana and explore traces"
echo ""
echo "Verification:"
echo "  kubectl get pods -n observability"
echo "  ./scripts/verify-otel-to-tempo.sh"
echo ""
echo "Stop everything: ./clean.sh"
echo "====================================="