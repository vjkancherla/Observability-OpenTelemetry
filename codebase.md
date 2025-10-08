# .gitignore

```
# Maven
target/
pom.xml.tag
pom.xml.releaseBackup
pom.xml.versionsBackup
pom.xml.next
release.properties
dependency-reduced-pom.xml
buildNumber.properties
.mvn/timing.properties
.mvn/wrapper/maven-wrapper.jar

# IDE
.idea/
*.iml
*.iws
*.ipr
.vscode/
.settings/
.project
.classpath

# OS
.DS_Store
Thumbs.db

# Logs
*.log

# OpenTelemetry
otel/*.jar

```

# .skaffoldignore

```
**/target/
**/bin/
**/.git/
**/node_modules/
**/test-logs/
```

# alerts/alertmanager-webhook.yaml

```yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: otel-trace-correlation
  namespace: observability
  labels:
    alertmanagerConfig: main
spec:
  route:
    groupBy: ['alertname', 'trace_id']
    groupWait: 5s
    groupInterval: 30s
    repeatInterval: 2m
    receiver: 'otel-correlation-webhook'

  receivers:
  - name: 'otel-correlation-webhook'
    webhookConfigs:
    - url: 'https://webhook-test.com/b05fc179dd8b97132b436df4cb3dfdd1'
      sendResolved: true
```

# alerts/prometheus-rules-cronjob-alerts.yaml

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cronjob-otel-alerts
  namespace: observability
  labels:
    prometheus: kube-prometheus
    role: alert-rules
    release: dev-prometheus
spec:
  groups:
  - name: cronjob-otel-traces
    interval: 30s
    rules:
    # Alert when CronJob fails (from span metrics)
    - alert: CronJobFailedWithTraceID
      expr: |
        calls_total{service_name="request-sender", span_kind="SPAN_KIND_CLIENT", http_status_code="500"} > 0
      for: 0m
      labels:
        severity: warning
        service: request-sender
        component: cronjob
      annotations:
        summary: "CronJob failed - Trace ID: {{ $labels.trace_id }}"
        description: "CronJob request failed with HTTP 500. Service: {{ $labels.service_name }}, Status: {{ $labels.http_status_code }}"
        trace_url: "http://localhost:3000/explore?left=%5B%22now-1h%22,%22now%22,%22tempo%22,%7B%22query%22:%22{{ $labels.trace_id }}%22%7D%5D"
        logs_url: "http://localhost:3000/explore?left=%5B%22now-1h%22,%22now%22,%22loki%22,%7B%22expr%22:%22%7Bservice_name%3D%5C%22request-sender%5C%22%7D%20%7C%3D%20%5C%22{{ $labels.trace_id }}%5C%22%22%7D%5D"
    
    # Alert when CronJob hasn't run recently
    - alert: CronJobNotRunningRecently
      expr: |
        (time() - max(calls_total{service_name="request-sender"}) > 300) or absent(calls_total{service_name="request-sender"})
      for: 2m
      labels:
        severity: critical
        service: request-sender
        component: cronjob
      annotations:
        summary: "CronJob hasn't run in over 5 minutes"
        description: "The request-sender CronJob should run every minute but hasn't been seen recently."
```

# clean.sh

```sh
#!/bin/bash

echo "🧹 Cleaning up..."

pkill -f "kubectl port-forward" 2>/dev/null || true
k3d cluster delete mycluster 2>/dev/null || true

echo "✅ Done!"
```

# deploy-minimal-observability-stack.sh

```sh
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

echo ""
echo "Step 4: Port Forwarding"
echo "======================="

echo "Starting port-forwards..."
pkill -f "kubectl port-forward" 2>/dev/null || true

kubectl port-forward -n observability svc/dev-tempo 3100:3100 >/dev/null 2>&1 &

sleep 2
echo "   ✅ Port-forwards started"

echo ""
echo "====================================="
echo "Deployment Complete!"
echo "====================================="
echo ""
echo "Services available:"
echo "  - Tempo API: http://localhost:3100"
echo ""
echo "Verify deployment:"
echo "  kubectl get pods -n observability"
echo ""
echo "Test trace collection:"
echo "  1. Wait for CronJob to run (every minute)"
echo "  2. Get trace_id from CronJob logs"
echo "  3. Query: curl http://localhost:3100/api/traces/{trace_id}"
echo ""
echo "Stop everything: ./cleanup.sh"
echo "====================================="
```

# deploy-observability-stack.sh

```sh
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
```

# Dockerfile

```
FROM eclipse-temurin:17-jre-alpine

# Create app directory
WORKDIR /app

# Copy the jar file
COPY target/tracing-app-1.0.0.jar app.jar

# Copy OpenTelemetry Java agent
RUN mkdir -p /app/otel
COPY otel/opentelemetry-javaagent.jar /app/otel/opentelemetry-javaagent.jar

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run the application
# Note: OpenTelemetry Java agent will be added via javaagent flag when we integrate OTel
ENTRYPOINT ["java", "-jar", "/app/app.jar"]

```

# docs/about-otel.md

This is a minified file of type: .md - The file exists but has been excluded from the codebase digest.

# docs/design.md

This is a minified file of type: .md - The file exists but has been excluded from the codebase digest.

# docs/otel-logs-verification.md

This is a minified file of type: .md - The file exists but has been excluded from the codebase digest.

# docs/trace-spans-creation.md

This is a minified file of type: .md - The file exists but has been excluded from the codebase digest.

# docs/trace-spans-mdc.md

This is a minified file of type: .md - The file exists but has been excluded from the codebase digest.

# observability-stack-helm-values/grafana.yaml

```yaml
adminPassword: admin

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 100m
    memory: 128Mi

persistence:
  enabled: false

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://dev-prometheus-kube-promet-prometheus.observability.svc.cluster.local:9090
      isDefault: true
      jsonData:
        exemplarTraceIdDestinations:
          - name: trace_id
            datasourceUid: tempo
    
    - name: Tempo
      type: tempo
      uid: tempo
      url: http://dev-tempo.observability.svc.cluster.local:3100
      jsonData:
        tracesToLogsV2:
          datasourceUid: loki
          spanStartTimeShift: '-1h'
          spanEndTimeShift: '1h'
          filterByTraceID: true
          filterBySpanID: false
          customQuery: false
          tags:
            - key: 'service.name'
              value: 'service_name'
        tracesToMetrics:
          datasourceUid: prometheus
          spanStartTimeShift: '-1h'
          spanEndTimeShift: '1h'
        serviceMap:
          datasourceUid: prometheus
        nodeGraph:
          enabled: true
    
    - name: Loki
      type: loki
      uid: loki
      url: http://dev-loki.observability.svc.cluster.local:3100
      jsonData:
        maxLines: 1000
        derivedFields:
          - datasourceUid: tempo
            matcherRegex: "trace_id=(\\w+)"
            name: TraceID
            url: '$${__value.raw}'

dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
    - name: 'default'
      orgId: 1
      folder: ''
      type: file
      disableDeletion: false
      editable: true
      options:
        path: /var/lib/grafana/dashboards/default

dashboards:
  default:
    traces-dashboard:
      json: |
        {
          "annotations": {
            "list": []
          },
          "editable": true,
          "fiscalYearStartMonth": 0,
          "graphTooltip": 0,
          "id": 1,
          "links": [],
          "panels": [
            {
              "datasource": {
                "type": "tempo",
                "uid": "tempo"
              },
              "fieldConfig": {
                "defaults": {},
                "overrides": []
              },
              "gridPos": {
                "h": 20,
                "w": 24,
                "x": 0,
                "y": 0
              },
              "id": 1,
              "targets": [
                {
                  "datasource": {
                    "type": "tempo",
                    "uid": "tempo"
                  },
                  "queryType": "traceql",
                  "refId": "A",
                  "query": "{}"
                }
              ],
              "title": "Traces",
              "type": "traces"
            }
          ],
          "refresh": "30s",
          "schemaVersion": 41,
          "tags": [],
          "templating": {
            "list": [
              {
                "current": {
                  "text": "",
                  "value": ""
                },
                "name": "trace_id",
                "type": "textbox",
                "label": "Trace ID"
              }
            ]
          },
          "time": {
            "from": "now-1h",
            "to": "now"
          },
          "timepicker": {},
          "timezone": "browser",
          "title": "Traces",
          "uid": "traces-dashboard",
          "version": 1
        }
    
    logs-dashboard:
      json: |
        {
          "annotations": {
            "list": []
          },
          "editable": true,
          "fiscalYearStartMonth": 0,
          "graphTooltip": 0,
          "id": 2,
          "links": [],
          "panels": [
            {
              "datasource": {
                "type": "loki",
                "uid": "loki"
              },
              "fieldConfig": {
                "defaults": {},
                "overrides": []
              },
              "gridPos": {
                "h": 20,
                "w": 24,
                "x": 0,
                "y": 0
              },
              "id": 1,
              "options": {
                "dedupStrategy": "none",
                "enableInfiniteScrolling": false,
                "enableLogDetails": true,
                "prettifyLogMessage": false,
                "showCommonLabels": false,
                "showLabels": true,
                "showTime": true,
                "sortOrder": "Descending",
                "wrapLogMessage": true
              },
              "pluginVersion": "12.0.0",
              "targets": [
                {
                  "expr": "{service_name=~\"$service\"} |= \"$trace_id\"",
                  "refId": "A"
                }
              ],
              "title": "Logs",
              "type": "logs"
            }
          ],
          "refresh": "30s",
          "schemaVersion": 41,
          "tags": [],
          "templating": {
            "list": [
              {
                "current": {
                  "text": ".*",
                  "value": ".*"
                },
                "name": "trace_id",
                "type": "textbox",
                "label": "Trace ID",
                "options": [
                  {
                    "text": ".*",
                    "value": ".*"
                  }
                ]
              },
              {
                "current": {
                  "text": ".*",
                  "value": ".*"
                },
                "name": "service",
                "type": "textbox",
                "label": "Service",
                "options": [
                  {
                    "text": ".*",
                    "value": ".*"
                  }
                ]
              }
            ]
          },
          "time": {
            "from": "now-1h",
            "to": "now"
          },
          "timepicker": {},
          "timezone": "browser",
          "title": "Logs",
          "uid": "logs-dashboard",
          "version": 1
        }
```

# observability-stack-helm-values/loki.yaml

```yaml
deploymentMode: SingleBinary

loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: 'filesystem'
  limits_config:
    retention_period: 24h
    ingestion_rate_mb: 4
    ingestion_burst_size_mb: 6
  schemaConfig:
    configs:
      - from: 2024-04-01
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: loki_index_
          period: 24h

singleBinary:
  replicas: 1
  persistence:
    enabled: true
    size: 200Mi
  resources:
    requests:
      cpu: 50m
      memory: 256Mi
    limits:
      cpu: 200m
      memory: 512Mi

# Explicitly disable SimpleScalable components
write:
  replicas: 0
read:
  replicas: 0  
backend:
  replicas: 0

# Disable memory-hungry caching components
chunksCache:
  enabled: false
resultsCache:
  enabled: false
memcached:
  enabled: false

# Disable other optional components
test:
  enabled: false
monitoring:
  enabled: false
lokiCanary:
  enabled: false
```

# observability-stack-helm-values/otel-collector-minimal.yaml

```yaml
mode: deployment

# Required: explicit image configuration
image:
  repository: otel/opentelemetry-collector-k8s
  tag: 0.115.1

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi

# Enable ports for receiving telemetry
ports:
  otlp:
    enabled: true
    containerPort: 4317
    servicePort: 4317
    protocol: TCP
  otlp-http:
    enabled: true
    containerPort: 4318
    servicePort: 4318
    protocol: TCP

config:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: ${env:MY_POD_IP}:4317
        http:
          endpoint: ${env:MY_POD_IP}:4318
  
  processors:
    batch:
      timeout: 5s
      send_batch_size: 512
    
    memory_limiter:
      check_interval: 5s
      limit_percentage: 80
  
  exporters:
    # Export traces to Tempo
    otlp/tempo:
      endpoint: dev-tempo.observability.svc.cluster.local:4317
      tls:
        insecure: true
    
    # Keep debug exporter for troubleshooting
    debug:
      verbosity: detailed
  
  extensions:
    health_check:
      endpoint: ${env:MY_POD_IP}:13133
  
  service:
    extensions: [health_check]
    pipelines:
      # Traces pipeline - export to both Tempo and debug
      traces:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [otlp/tempo, debug]
      
      # Logs pipeline - still just debug for now  
      logs:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [debug]

# Service configuration
service:
  type: ClusterIP
```

# observability-stack-helm-values/otel-collector.yaml

```yaml
mode: deployment

image:
  repository: otel/opentelemetry-collector-k8s
  tag: 0.115.1

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 200m
    memory: 512Mi

# Enable metrics port for Prometheus scraping
ports:
  otlp:
    enabled: true
    containerPort: 4317
    servicePort: 4317
    protocol: TCP
  otlp-http:
    enabled: true
    containerPort: 4318
    servicePort: 4318
    protocol: TCP
  metrics:
    enabled: true
    containerPort: 8889
    servicePort: 8889
    protocol: TCP

config:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: ${env:MY_POD_IP}:4317
        http:
          endpoint: ${env:MY_POD_IP}:4318
  
  processors:
    batch:
      timeout: 10s
      send_batch_size: 1024
    
    resource:
      attributes:
        - key: cluster.name
          value: k3d-mycluster
          action: upsert
    
    attributes:
      actions:
        - key: service.name
          action: upsert
          from_attribute: service.name
    
    # Memory limiter (required)
    memory_limiter:
      check_interval: 5s
      limit_percentage: 80
      spike_limit_percentage: 25
  
  exporters:
    # Tempo exporter for traces
    otlp/tempo:
      endpoint: dev-tempo.observability.svc.cluster.local:4317
      tls:
        insecure: true
    
    # Prometheus exporter for metrics
    prometheus:
      endpoint: ${env:MY_POD_IP}:8889
      resource_to_telemetry_conversion:
        enabled: true
    
    # Loki exporter for logs
    loki:
      endpoint: http://dev-loki.observability.svc.cluster.local:3100/loki/api/v1/push
      labels:
        resource:
          service.name: "service_name"
        attributes:
          level: "level"
    
    # Debug exporter (optional, for troubleshooting)
    debug:
      verbosity: detailed
  
  connectors:
    # Span Metrics Connector - KEY COMPONENT
    # Generates metrics from spans with trace_id as exemplar
    spanmetrics:
      histogram_buckets: [100us, 1ms, 2ms, 6ms, 10ms, 100ms, 250ms]
      dimensions:
        - name: http.method
          default: GET
        - name: http.status_code
        - name: service.name
      exemplars:
        enabled: true
      metrics_flush_interval: 15s
  
  extensions:
    # Health check extension (required)
    health_check:
      endpoint: ${env:MY_POD_IP}:13133
  
  service:
    extensions: [health_check]
    pipelines:
      # Traces pipeline
      traces:
        receivers: [otlp]
        processors: [memory_limiter, batch, resource, attributes]
        exporters: [otlp/tempo, spanmetrics]
      
      # Metrics pipeline (includes span-generated metrics)
      metrics:
        receivers: [spanmetrics]
        processors: [memory_limiter, batch, resource]
        exporters: [prometheus]
      
      # Logs pipeline
      logs:
        receivers: [otlp]
        processors: [memory_limiter, batch, resource, attributes]
        exporters: [loki]

# Service configuration
service:
  type: ClusterIP

# ServiceMonitor for Prometheus scraping
serviceMonitor:
  enabled: true
  extraLabels:
    release: dev-prometheus
```

# observability-stack-helm-values/prometheus.yaml

```yaml
grafana:
  enabled: false

prometheus:
  prometheusSpec:
    retention: 2h
    
    # Enable exemplar storage for trace linking
    enableFeatures:
      - exemplar-storage
    
    resources:
      requests:
        cpu: 50m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
    
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          resources:
            requests:
              storage: 200Mi
    
    # Scrape OTel Collector metrics
    additionalScrapeConfigs:
      - job_name: 'otel-collector'
        static_configs:
          - targets: ['otel-collector.observability.svc.cluster.local:8889']

alertmanager:
  enabled: true
  alertmanagerSpec:
    resources:
      requests:
        cpu: 25m
        memory: 32Mi
      limits:
        cpu: 50m
        memory: 64Mi
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          resources:
            requests:
              storage: 200Mi

nodeExporter:
  enabled: false

kubeStateMetrics:
  enabled: true
```

# observability-stack-helm-values/tempo.yaml

```yaml
tempo:
  repository: grafana/tempo
  tag: 2.7.1
  
   Minimal resources for low-memory environments
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 100m
      memory: 256Mi
  
  storage:
    trace:
      backend: local
      local:
        path: /var/tempo/traces
      wal:
        path: /var/tempo/wal
      # Reduce block size and cache
      block:
        encoding: zstd
      pool:
        max_workers: 10
        queue_depth: 2000
  
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318
  
  # Reduce memory usage
  querier:
    max_concurrent_queries: 5
  
  # Minimal ingester settings
  ingester:
    max_block_duration: 5m
    max_block_bytes: 10485760  # 10MB

persistence:
  enabled: true
  size: 200Mi  # Reduced from 1Gi
  accessModes:
    - ReadWriteOnce

service:
  type: ClusterIP
```

# otel/opentelemetry-javaagent.jar

This is a binary file of the type: Binary

# pom.xml

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.2.5</version>
        <relativePath/>
    </parent>
    
    <groupId>com.example</groupId>
    <artifactId>tracing-app</artifactId>
    <version>1.0.0</version>
    <name>tracing-app</name>
    <description>Spring Boot application with OpenTelemetry tracing</description>
    
    <properties>
        <java.version>17</java.version>
        <opentelemetry.version>1.36.0</opentelemetry.version>
    </properties>
    
    <dependencies>
        <!-- Spring Boot Web -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        
        <!-- Spring Boot Actuator for health checks -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        
        <!-- Logging with SLF4J and Logback (included in spring-boot-starter-web) -->
        
        <!-- Optional: For structured JSON logging -->
        <dependency>
            <groupId>net.logstash.logback</groupId>
            <artifactId>logstash-logback-encoder</artifactId>
            <version>7.4</version>
        </dependency>
        
        <!-- Test dependencies -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>
    
    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>

```

# README.md

```md
# Spring Boot Tracing Application

A Spring Boot application with OpenTelemetry tracing support for distributed observability.

## 🚀 Quick Start

### Prerequisites
- Java 17 or higher
- Maven 3.6+
- Docker (optional, for containerization)

### Build and Run

\`\`\`bash
# Build the application
mvn clean package

# Run locally
java -jar target/tracing-app-1.0.0.jar

# Access the application
curl http://localhost:8080/
\`\`\`

## 📍 Endpoints

| Endpoint | Method | Description | Response Code |
|----------|--------|-------------|---------------|
| `/` | GET | Home endpoint | 200 |
| `/simulate-error` | GET | Error simulation | 500 |
| `/health` | GET | Health check | 200 |
| `/metrics` | GET | Metrics | 200 |
| `/trace` | GET | Trace test | 200 |

## 🧪 Testing

### Test with W3C Trace Context
\`\`\`bash
curl -H "traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01" \
     http://localhost:8080/

curl -H "traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01" \
     http://localhost:8080/simulate-error
\`\`\`

### Expected Log Output (JSON)
\`\`\`json
{
  "timestamp": "2025-01-15T10:30:45.123Z",
  "level": "INFO",
  "service": "tracing-webapp",
  "message": "Home endpoint accessed successfully",
  "trace_id": "0af7651916cd43dd8448eb211c80319c"
}
\`\`\`

## 🐳 Docker

### Build Image
\`\`\`bash
docker build -t tracing-app:1.0.0 .
\`\`\`

### Run Container
\`\`\`bash
docker run -p 8080:8080 tracing-app:1.0.0
\`\`\`

## 🔧 Project Structure

\`\`\`
tracing-app/
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/example/tracingapp/
│   │   │       ├── TracingAppApplication.java
│   │   │       └── controller/
│   │   │           └── TracingController.java
│   │   └── resources/
│   │       ├── application.yml
│   │       └── logback-spring.xml
│   └── test/
├── Dockerfile
├── pom.xml
└── README.md
\`\`\`

## 🎯 Next Steps: OpenTelemetry Integration

### 1. Download OTel Java Agent
\`\`\`bash
wget https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar \
     -O otel/opentelemetry-javaagent.jar
\`\`\`

### 2. Run with OTel Agent, and log to Console
\`\`\`bash
JAVA_TOOL_OPTIONS="-javaagent:otel/opentelemetry-javaagent.jar" \
OTEL_SERVICE_NAME="tracing-webapp" \
OTEL_TRACES_EXPORTER="logging" \
OTEL_METRICS_EXPORTER="logging" \
OTEL_LOGS_EXPORTER="logging" \
OTEL_METRIC_EXPORT_INTERVAL="15000" \
java -jar target/tracing-app-1.0.0.jar
\`\`\`


## 📊 Observability Stack Integration

This application is designed to work with:
- **OpenTelemetry Collector** - Receives traces/metrics/logs
- **Grafana Tempo** - Stores distributed traces
- **Prometheus** - Stores metrics
- **Loki** - Stores logs
- **Grafana** - Unified visualization

## 🔗 W3C Trace Context

The application extracts `trace_id` from the W3C `traceparent` header:
- Format: `00-{trace_id}-{span_id}-{flags}`
- Example: `00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01`
- Automatically injects `trace_id` into logs via MDC

## 📝 License

This project is part of the OpenTelemetry observability stack demonstration.

```

# scripts/verify-otel-to-tempo.sh

```sh
#!/bin/bash

echo "Verification: OTel Collection + Tempo Storage"
echo "============================================="

# Check if port-forwards are active
check_port() {
    local port=$1
    local name=$2
    if nc -z localhost $port 2>/dev/null; then
        echo "✅ $name is accessible on port $port"
        return 0
    else
        echo "❌ $name is NOT accessible on port $port"
        echo "   Run: kubectl port-forward -n observability svc/$name $port:$port &"
        return 1
    fi
}

echo ""
echo "1. Checking Port Forwards"
echo "------------------------"
check_port 3100 "dev-tempo"
check_port 8080 "tracing-webapp-service"

echo ""
echo "2. Checking Pod Status"
echo "---------------------"
echo "OTel Collector:"
kubectl get pods -n observability -l app.kubernetes.io/name=opentelemetry-collector
echo ""
echo "Tempo:"
kubectl get pods -n observability -l app.kubernetes.io/name=tempo
echo ""
echo "Spring Boot App:"
kubectl get pods -n my-demo -l app=tracing-webapp

echo ""
echo "3. Checking OTel Collector Logs"
echo "-------------------------------"
echo "Looking for trace exports to Tempo..."
otel_logs=$(kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-collector --tail=100)

if echo "$otel_logs" | grep -qi "tempo\|export"; then
    echo "✅ OTel Collector has export activity"
else
    echo "⚠️  No export activity found in recent logs"
fi

if echo "$otel_logs" | grep -q "Span"; then
    echo "✅ OTel Collector is receiving spans"
    span_count=$(echo "$otel_logs" | grep -c "Span" || echo "0")
    echo "   Found $span_count span references in recent logs"
else
    echo "⚠️  No spans found in recent OTel Collector logs"
fi

echo ""
echo "4. Checking Spring Boot App Logs"
echo "--------------------------------"
echo "Looking for trace_id in application logs..."
app_logs=$(kubectl logs -n my-demo -l app=tracing-webapp --tail=20)

if echo "$app_logs" | grep -q "trace_id"; then
    echo "✅ Spring Boot app is generating traces with trace_id"
    echo "   Sample log:"
    echo "$app_logs" | grep "trace_id" | head -1 | jq -r '.message + " (trace_id: " + .trace_id + ")"' 2>/dev/null || echo "$app_logs" | grep "trace_id" | head -1
else
    echo "⚠️  No trace_id found in recent app logs"
fi

echo ""
echo "5. Waiting for CronJob Execution"
echo "--------------------------------"
echo "Checking for recent CronJob runs..."

latest_job=$(kubectl get jobs -n my-demo -l app=request-sender --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null)

if [ -n "$latest_job" ]; then
    echo "✅ Found CronJob execution: $latest_job"
    
    trace_id=$(kubectl logs -n my-demo job/$latest_job 2>/dev/null | grep "Trace ID:" | awk '{print $NF}' | tail -1)
    
    if [ -n "$trace_id" ]; then
        echo "✅ Extracted trace_id: $trace_id"
        
        echo ""
        echo "6. Querying Tempo for Trace"
        echo "---------------------------"
        echo "Waiting 5 seconds for trace to be written to Tempo..."
        sleep 5
        
        tempo_response=$(curl -s "http://localhost:3100/api/traces/$trace_id")
        
        if [ -z "$tempo_response" ]; then
            echo "❌ Empty response from Tempo"
        elif echo "$tempo_response" | jq -e '.batches[0]' >/dev/null 2>&1; then
            echo "✅ SUCCESS: Trace found in Tempo!"
            
            echo ""
            echo "Trace Details:"
            echo "  Trace ID: $trace_id"
            
            span_count=$(echo "$tempo_response" | jq '[.batches[].scopeSpans[].spans[]] | length')
            echo "  Total Spans: $span_count"
            
            echo "  Services involved:"
            echo "$tempo_response" | jq -r '.batches[].resource.attributes[]? | select(.key=="service.name") | .value.stringValue' | sed 's/^/    - /'
            
            echo ""
            echo "Span breakdown:"
            echo "$tempo_response" | jq -r '.batches[].scopeSpans[].spans[]? | "  - \(.name) (kind: \(.kind)) - status: \(.status.code // "unset")"'
            
            echo ""
            parent_count=$(echo "$tempo_response" | jq '[.batches[].scopeSpans[].spans[] | select(.parentSpanId != null)] | length')
            if [ -n "$parent_count" ] && [ "$parent_count" -gt 0 ]; then
                echo "  ✅ Parent-child span relationship detected ($parent_count child span(s))"
            else
                echo "  ⚠️  No parent-child relationships found"
            fi
        else
            echo "❌ Trace not found in Tempo"
        fi
        
        echo ""
        echo "7. Direct Tempo API Queries"
        echo "--------------------------"
        echo "Tempo health:"
        curl -s http://localhost:3100/ready && echo "  ✅ Tempo is ready" || echo "  ❌ Tempo is not ready"
        
        echo ""
        echo "Search for traces (last 1 hour):"
        if date --version >/dev/null 2>&1; then
            start_time=$(date -u -d '1 hour ago' +%s)
            end_time=$(date -u +%s)
        else
            start_time=$(date -u -v-1H +%s)
            end_time=$(date -u +%s)
        fi
        
        search_response=$(curl -s "http://localhost:3100/api/search?tags=service.name=request-sender&start=${start_time}&end=${end_time}")
        trace_count=$(echo "$search_response" | jq -r '.traces | length' 2>/dev/null || echo "0")
        echo "  Found $trace_count trace(s) from request-sender service"
        
    else
        echo "❌ Could not extract trace_id from CronJob logs"
        kubectl logs -n my-demo job/$latest_job --tail=10
    fi
else
    echo "⚠️  No CronJob executions found yet"
    echo "   CronJob runs every minute. Wait and check again."
fi

echo ""
echo "============================================="
echo "Verification Summary"
echo "============================================="
echo ""
echo "What we verified:"
echo "  1. OTel Collector is receiving spans from applications"
echo "  2. Traces are being stored in Tempo"
echo "  3. Distributed tracing works (parent-child span relationships)"
echo "  4. Both services (CronJob + Spring Boot) are participating in traces"
echo ""
echo "Complete trace flow:"
echo "  CronJob (CLIENT span) → HTTP request → Spring Boot (SERVER span)"
echo "  Both spans share the same trace_id, forming a distributed trace"
echo ""
echo "Manual verification commands:"
echo "  Query trace: curl http://localhost:3100/api/traces/{trace_id} | jq"
echo "  Search traces: curl 'http://localhost:3100/api/search?tags=service.name=request-sender' | jq"
echo ""
echo "============================================="
```

# skaffold.yaml

```yaml
apiVersion: skaffold/v2beta16
kind: Config
metadata:
  name: tracing-app

build:
  local:
    push: false
    useBuildkit: true
  artifacts:
  - image: vjkancherla/tracing-app
    docker:
      dockerfile: Dockerfile

deploy:
  helm:
    releases:
    - name: tracing-app
      chartPath: tracing-app-helm-chart
      namespace: my-demo
      createNamespace: true

portForward:
- resourceType: service
  resourceName: tracing-webapp-service
  namespace: my-demo
  port: 8080
  localPort: 8080


```

# src/main/java/com/example/tracingapp/controller/TracingController.java

```java
package com.example.tracingapp.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

@RestController
public class TracingController {

    private static final Logger logger = LoggerFactory.getLogger(TracingController.class);

    @GetMapping("/")
    public ResponseEntity<Map<String, Object>> home(
            @RequestHeader(value = "traceparent", required = false) String traceparent) {
        
        String traceId = extractTraceId(traceparent);
        if (traceId != null) {
            MDC.put("trace_id", traceId);
        }
        
        logger.info("Home endpoint accessed successfully");
        
        Map<String, Object> response = new HashMap<>();
        response.put("status", "success");
        response.put("service", "tracing-webapp");
        response.put("timestamp", Instant.now().toString());
        response.put("trace_id", traceId);
        
        MDC.clear();
        return ResponseEntity.ok(response);
    }

    @GetMapping("/simulate-error")
    public ResponseEntity<Map<String, Object>> simulateError(
            @RequestHeader(value = "traceparent", required = false) String traceparent) {
        
        String traceId = extractTraceId(traceparent);
        if (traceId != null) {
            MDC.put("trace_id", traceId);
        }
        
        logger.error("Simulated error - Database connection timeout");
        
        Map<String, Object> response = new HashMap<>();
        response.put("error", "Database connection timeout");
        response.put("service", "tracing-webapp");
        response.put("timestamp", Instant.now().toString());
        response.put("trace_id", traceId);
        
        MDC.clear();
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(response);
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> health() {
        Map<String, Object> response = new HashMap<>();
        response.put("status", "healthy");
        response.put("service", "tracing-webapp");
        response.put("timestamp", Instant.now().toString());
        
        return ResponseEntity.ok(response);
    }

    @GetMapping("/metrics")
    public ResponseEntity<Map<String, Object>> metrics() {
        Map<String, Object> response = new HashMap<>();
        response.put("service", "tracing-webapp");
        response.put("status", "running");
        response.put("timestamp", Instant.now().toString());
        
        return ResponseEntity.ok(response);
    }

    @GetMapping("/trace")
    public ResponseEntity<Map<String, Object>> trace(
            @RequestHeader(value = "traceparent", required = false) String traceparent) {
        
        String traceId = extractTraceId(traceparent);
        if (traceId != null) {
            MDC.put("trace_id", traceId);
        }
        
        logger.info("Trace endpoint accessed");
        
        Map<String, Object> response = new HashMap<>();
        response.put("message", "Trace endpoint accessed");
        response.put("service", "tracing-webapp");
        response.put("timestamp", Instant.now().toString());
        response.put("trace_id", traceId);
        
        MDC.clear();
        return ResponseEntity.ok(response);
    }

    /**
     * Extract trace_id from W3C traceparent header
     * Format: "00-{trace_id}-{span_id}-{flags}"
     */
    private String extractTraceId(String traceparent) {
        if (traceparent == null || traceparent.isEmpty()) {
            return null;
        }
        
        String[] parts = traceparent.split("-");
        if (parts.length >= 2) {
            return parts[1]; // trace_id is the second part
        }
        
        return null;
    }
}

```

# src/main/java/com/example/tracingapp/TracingAppApplication.java

```java
package com.example.tracingapp;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class TracingAppApplication {

    public static void main(String[] args) {
        SpringApplication.run(TracingAppApplication.class, args);
    }
}

```

# src/main/resources/application.yml

```yml
server:
  port: 8080

spring:
  application:
    name: tracing-webapp

# Actuator endpoints
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics
  endpoint:
    health:
      show-details: always

# Logging configuration
logging:
  level:
    root: INFO
    com.example.tracingapp: DEBUG
  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss} - %msg%n"

```

# src/main/resources/logback-spring.xml

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <include resource="org/springframework/boot/logging/logback/defaults.xml"/>
    
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder">
            <customFields>{"service":"tracing-webapp"}</customFields>
            <fieldNames>
                <timestamp>timestamp</timestamp>
                <message>message</message>
                <logger>logger</logger>
                <thread>thread</thread>
                <level>level</level>
            </fieldNames>
            <includeMdcKeyName>trace_id</includeMdcKeyName>
            <includeMdcKeyName>span_id</includeMdcKeyName>
        </encoder>
    </appender>

    <root level="INFO">
        <appender-ref ref="CONSOLE"/>
    </root>
    
    <logger name="com.example.tracingapp" level="DEBUG"/>
</configuration>

```

# tracing-app-helm-chart/Chart.yaml

```yaml
apiVersion: v2
name: otel-tracing-app
description: A Helm chart for Spring Boot application with OpenTelemetry tracing
type: application
version: 0.1.0
appVersion: "1.0.0"
keywords:
  - tracing
  - opentelemetry
  - spring-boot
  - observability
  - grafana
  - tempo
home: https://github.com/your-org/otel-tracing-app
maintainers:
  - name: Your Name
    email: your.email@example.com
```

# tracing-app-helm-chart/templates/_helpers.tpl

```tpl
{{/*
We don't actually need any helpers for this simple chart.
Keeping the file for Helm convention, but it's empty.
*/}}
```

# tracing-app-helm-chart/templates/cronjob.yaml

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ .Values.cronjob.name }}
  labels:
    app: {{ .Values.cronjob.name }}
spec:
  schedule: {{ .Values.cronjob.schedule | quote }}
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 0
      template:
        metadata:
          labels:
            app: {{ .Values.cronjob.name }}
        spec:
          containers:
          - name: request-sender
            image: "{{ .Values.cronjob.image.repository }}:{{ .Values.cronjob.image.tag }}"
            env:
            - name: OTEL_COLLECTOR_ENDPOINT
              value: {{ .Values.otel.collector.httpEndpoint | quote }}
            - name: OTEL_SERVICE_NAME
              value: {{ .Values.cronjob.name | quote }}
            - name: TARGET_SERVICE
              value: "{{ .Values.webapp.name }}-service"
            command:
            - /bin/sh
            - -c
            - |
              # Generate W3C Trace Context
              TRACE_ID=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -n 1)
              SPAN_ID=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 16 | head -n 1)
              TRACEPARENT="00-${TRACE_ID}-${SPAN_ID}-01"
              
              echo "=========================================="
              echo "CronJob Execution Started"
              echo "=========================================="
              echo "Service: ${OTEL_SERVICE_NAME}"
              echo "Trace ID: ${TRACE_ID}"
              echo "Span ID: ${SPAN_ID}"
              echo ""
              
              # Record start time (nanoseconds)
              START_TIME_NS=$(date +%s%N)
              
              # Every 5th minute = error endpoint, otherwise success endpoint
              CURRENT_MINUTE=$(date +%M | sed 's/^0//')
              if [ $((CURRENT_MINUTE % 5)) -eq 0 ]; then
                ENDPOINT="/simulate-error"
                EXPECTED_CODE="500"
                JOB_TYPE="error_simulation"
                echo "ERROR SIMULATION (minute $CURRENT_MINUTE)"
              else
                ENDPOINT="/"
                EXPECTED_CODE="200"
                JOB_TYPE="success"
                echo "SUCCESS TEST (minute $CURRENT_MINUTE)"
              fi
              
              echo "Endpoint: ${ENDPOINT}"
              echo "Expected: ${EXPECTED_CODE}"
              echo ""
              
              # Make HTTP request
              echo "Making request..."
              RESPONSE_CODE=$(curl -H "traceparent: ${TRACEPARENT}" \
                   -s -o /tmp/response.json -w "%{http_code}" \
                   "http://${TARGET_SERVICE}:8080${ENDPOINT}" || echo "000")
              
              # Record end time
              END_TIME_NS=$(date +%s%N)
              
              echo "Response: ${RESPONSE_CODE}"
              echo ""
              
              # Determine span status
              if [ "$RESPONSE_CODE" = "$EXPECTED_CODE" ]; then
                if [ "$JOB_TYPE" = "error_simulation" ]; then
                  SPAN_STATUS_CODE=2  # ERROR
                  SPAN_STATUS_MESSAGE="Expected error simulation completed"
                  JOB_STATUS="failed"
                  echo "Expected failure occurred"
                else
                  SPAN_STATUS_CODE=1  # OK
                  SPAN_STATUS_MESSAGE="Success"
                  JOB_STATUS="success"
                  echo "Request succeeded"
                fi
              else
                SPAN_STATUS_CODE=2  # ERROR
                SPAN_STATUS_MESSAGE="Unexpected response code: ${RESPONSE_CODE}"
                JOB_STATUS="failed"
                echo "Unexpected response!"
              fi
              
              # Create OTLP span payload - this should be the PARENT span
              cat > /tmp/span.json <<EOF
              {
                "resourceSpans": [{
                  "resource": {
                    "attributes": [
                      {"key": "service.name", "value": {"stringValue": "${OTEL_SERVICE_NAME}"}},
                      {"key": "service.version", "value": {"stringValue": "1.0.0"}}
                    ]
                  },
                  "scopeSpans": [{
                    "scope": {
                      "name": "cronjob-manual-instrumentation"
                    },
                    "spans": [{
                      "traceId": "${TRACE_ID}",
                      "spanId": "${SPAN_ID}",
                      "name": "http_request",
                      "kind": 3,
                      "startTimeUnixNano": "${START_TIME_NS}",
                      "endTimeUnixNano": "${END_TIME_NS}",
                      "attributes": [
                        {"key": "http.method", "value": {"stringValue": "GET"}},
                        {"key": "http.url", "value": {"stringValue": "http://${TARGET_SERVICE}:8080${ENDPOINT}"}},
                        {"key": "http.status_code", "value": {"intValue": ${RESPONSE_CODE}}},
                        {"key": "job.type", "value": {"stringValue": "${JOB_TYPE}"}},
                        {"key": "job.status", "value": {"stringValue": "${JOB_STATUS}"}},
                        {"key": "job.expected_code", "value": {"intValue": ${EXPECTED_CODE}}},
                        {"key": "component", "value": {"stringValue": "cronjob"}}
                      ],
                      "status": {
                        "code": ${SPAN_STATUS_CODE},
                        "message": "${SPAN_STATUS_MESSAGE}"
                      }
                    }]
                  }]
                }]
              }
              EOF
              
              # Send span to OTel Collector
              echo "Sending span to OTel Collector..."
              HTTP_STATUS=$(curl -X POST \
                -H "Content-Type: application/json" \
                -d @/tmp/span.json \
                "${OTEL_COLLECTOR_ENDPOINT}/v1/traces" \
                -s -o /dev/null -w "%{http_code}")
              
              if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "202" ]; then
                echo "Span sent successfully (HTTP ${HTTP_STATUS})"
              else
                echo "Failed to send span (HTTP ${HTTP_STATUS})"
              fi
              
              echo ""
              echo "=========================================="
              echo "Summary"
              echo "=========================================="
              echo "Job Type: ${JOB_TYPE}"
              echo "Job Status: ${JOB_STATUS}"
              echo "Trace ID: ${TRACE_ID}"
              echo "Grafana: http://localhost:3000/explore?trace_id=${TRACE_ID}"
              echo "=========================================="
              
              # Exit with error for failed jobs
              if [ "$JOB_STATUS" = "failed" ]; then
                exit 1
              fi
          restartPolicy: Never
```

# tracing-app-helm-chart/templates/deployment.yaml

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.webapp.name }}
  labels:
    app: {{ .Values.webapp.name }}
spec:
  replicas: {{ .Values.webapp.replicas }}
  selector:
    matchLabels:
      app: {{ .Values.webapp.name }}
  template:
    metadata:
      labels:
        app: {{ .Values.webapp.name }}
    spec:
      containers:
      - name: {{ .Values.webapp.name }}
        image: "{{ .Values.webapp.image.repository }}:{{ .Values.webapp.image.tag }}"
        ports:
        - containerPort: 8080
        
        env:
        - name: JAVA_TOOL_OPTIONS
          value: "-javaagent:/app/otel/opentelemetry-javaagent.jar"
        - name: OTEL_SERVICE_NAME
          value: {{ .Values.webapp.name | quote }}
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: {{ .Values.otel.collector.grpcEndpoint | quote }}
        - name: OTEL_EXPORTER_OTLP_PROTOCOL
          value: {{ .Values.otel.exporter.protocol | default "http/protobuf" | quote }}
        - name: OTEL_TRACES_EXPORTER
          value: {{ .Values.otel.exporter.tracesExporter | quote }}
        - name: OTEL_METRICS_EXPORTER
          value: {{ .Values.otel.exporter.metricsExporter | quote }}
        - name: OTEL_LOGS_EXPORTER
          value: {{ .Values.otel.exporter.logsExporter | quote }}
        
        resources:
          {{- toYaml .Values.webapp.resources | nindent 10 }}
        
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: {{ .Values.webapp.livenessProbe.initialDelaySeconds | default 30 }}
          periodSeconds: {{ .Values.webapp.livenessProbe.periodSeconds | default 10 }}
        
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: {{ .Values.webapp.readinessProbe.initialDelaySeconds | default 10 }}
          periodSeconds: {{ .Values.webapp.readinessProbe.periodSeconds | default 5 }}
```

# tracing-app-helm-chart/templates/service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.webapp.name }}-service
  labels:
    app: {{ .Values.webapp.name }}
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: 8080
  selector:
    app: {{ .Values.webapp.name }}
```

# tracing-app-helm-chart/values.yaml

```yaml
# OpenTelemetry Configuration (shared)
otel:
  collector:
    # HTTP endpoint (for Java agent - use HTTP protocol on port 4318)
    grpcEndpoint: "http://otel-collector-opentelemetry-collector.observability.svc.cluster.local:4318"
    # HTTP endpoint (for CronJob manual instrumentation)
    httpEndpoint: "http://otel-collector-opentelemetry-collector.observability.svc.cluster.local:4318"
  
  exporter:
    # Default: send to OTel Collector
    tracesExporter: "otlp"
    metricsExporter: "otlp"
    logsExporter: "otlp"
    # Explicitly set protocol to HTTP
    protocol: "http/protobuf"

# Spring Boot Webapp
webapp:
  name: tracing-webapp
  replicas: 1
  image:
    repository: vjkancherla/tracing-app  # Keep using your image
    tag: "1.0.0"
  
  # Add health probe configuration
  livenessProbe:
    initialDelaySeconds: 60
    periodSeconds: 10
  readinessProbe:
    initialDelaySeconds: 30
    periodSeconds: 5
  
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 200m
      memory: 256Mi

# CronJob
cronjob:
  name: request-sender
  schedule: "*/1 * * * *"
  image:
    repository: curlimages/curl
    tag: latest
```

