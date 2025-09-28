#!/bin/bash
set -e

echo "Creating k3d cluster..."
k3d cluster delete mycluster 2>/dev/null || true
k3d cluster create mycluster --agents 1 --wait
echo "   Cluster ready"

echo "Adding helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null
helm repo update >/dev/null
echo "   Repositories updated"

echo "Creating namespaces..."
kubectl create namespace observability 2>/dev/null || true
kubectl create namespace my-demo 2>/dev/null || true
echo "   Namespaces observability and my-demo created"

wait_for_release() {
  release=$1
  namespace=$2
  echo "   Waiting for pods of release '$release' in namespace '$namespace' to be ready..."
  kubectl rollout status -n "$namespace" deployment -l app.kubernetes.io/instance=$release --timeout=5m || true
  kubectl rollout status -n "$namespace" statefulset -l app.kubernetes.io/instance=$release --timeout=5m || true
  kubectl rollout status -n "$namespace" daemonset -l app.kubernetes.io/instance=$release --timeout=5m || true
}

echo "Deploying OpenTelemetry Collector (0.111.2)..."
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --version 0.111.2 --namespace observability -f observability-stack-helm-values/otel-collector.yaml --wait --timeout=5m
wait_for_release otel-collector observability
echo "   OTel Collector deployed"

echo "Deploying Tempo (1.18.2)..."
helm upgrade --install dev-tempo grafana/tempo \
  --version 1.18.2 --namespace observability -f observability-stack-helm-values/tempo.yaml --wait --timeout=5m
wait_for_release dev-tempo observability
echo "   Tempo deployed"

echo "Deploying Prometheus (v72.5.1)..."
helm upgrade --install dev-prometheus prometheus-community/kube-prometheus-stack \
  --version 72.5.1 --namespace observability -f observability-stack-helm-values/prometheus.yaml --wait --timeout=5m
wait_for_release dev-prometheus observability
echo "   Prometheus deployed"

echo "Deploying Loki (6.40.0)..."
helm upgrade --install dev-loki grafana/loki \
  --version 6.40.0 --namespace observability -f observability-stack-helm-values/loki.yaml --wait --timeout=5m
wait_for_release dev-loki observability
echo "   Loki deployed"

echo "Deploying Grafana (v9.0.0)..."
helm upgrade --install dev-grafana grafana/grafana \
  --version 9.0.0 --namespace observability -f observability-stack-helm-values/grafana.yaml --wait --timeout=5m
wait_for_release dev-grafana observability
echo "   Grafana deployed"

echo "Applying custom PrometheusRules and AlertmanagerConfig..."
kubectl apply -f alerts/prometheus-rules-cronjob-alerts.yaml
kubectl apply -f alerts/alertmanager-webhook.yaml
echo "   Custom rules and Alertmanager config applied"

echo "Building Spring Boot application..."
mvn clean package -DskipTests
echo "   Application built"

echo "Building Docker image..."
docker build -t tracing-app:1.0.0 .
echo "   Docker image built"

echo "Loading Docker image into k3d..."
k3d image import tracing-app:1.0.0 -c mycluster
echo "   Image loaded into cluster"

echo "Deploying Tracing App..."
helm upgrade --install dev-tracing ./helm-chart \
  --namespace my-demo --wait --timeout=5m
wait_for_release dev-tracing my-demo
echo "   Tracing app deployed"

echo "Starting port-forwards..."
kubectl port-forward -n observability svc/dev-grafana 3000:80 >/dev/null 2>&1 &
kubectl port-forward -n observability svc/dev-prometheus-kube-promet-prometheus 9090:9090 >/dev/null 2>&1 &
kubectl port-forward -n observability svc/dev-prometheus-kube-promet-alertmanager 9093:9093 >/dev/null 2>&1 &
kubectl port-forward -n observability svc/otel-collector 4318:4318 >/dev/null 2>&1 &
echo "   Port-forwards started (Grafana:3000, Prometheus:9090, Alertmanager:9093, OTel:4318)"

echo ""
echo "Deployment complete!"
echo "   Grafana: http://localhost:3000 (admin/admin)"
echo "   Prometheus: http://localhost:9090"
echo "   Alertmanager: http://localhost:9093"
echo "   OTel Collector: http://localhost:4318"
echo "   Stop: ./cleanup.sh"