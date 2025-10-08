# Verifying OTel Collector → Tempo Integration

## Purpose
This script validates that traces flow correctly from applications through the OpenTelemetry Collector to Tempo storage.

## Prerequisites
- k3d cluster running
- OTel Collector deployed
- Tempo deployed
- Spring Boot app deployed
- CronJob deployed
- Port-forwards active for Tempo (3100) and app (8080)

## Usage

```bash
cd scripts
chmod +x verify-otel-to-tempo.sh
./verify-otel-to-tempo.sh
```

## What It Checks

### 1. Port Forwards
Verifies that required services are accessible:
- Tempo API (port 3100)
- Spring Boot app (port 8080)

### 2. Pod Health
Checks if all components are running:
- OTel Collector pods
- Tempo pods
- Spring Boot app pods

### 3. OTel Collector Activity
- Confirms collector is receiving spans from applications
- Checks for export activity to Tempo

### 4. Application Traces
- Verifies Spring Boot app is generating traces with trace_id
- Shows sample log entry with trace context

### 5. CronJob Execution
- Finds the most recent CronJob run
- Extracts the trace_id from job logs

### 6. Tempo Trace Storage
Queries Tempo API with the extracted trace_id to verify:
- Trace was successfully stored
- Number of spans in the trace
- Services involved (request-sender, tracing-webapp)
- Span details (names, kinds, status codes)
- Parent-child span relationships (distributed tracing)

### 7. Tempo API Health
- Confirms Tempo is ready
- Searches for traces from the last hour

## Expected Output

**Success indicators:**
- ✅ 2 spans found in trace
- ✅ Both services present: request-sender and tracing-webapp
- ✅ Parent-child relationship detected (1 child span)
- ✅ Trace flow: CronJob CLIENT span → Spring Boot SERVER span

**Complete distributed trace structure:**
```
Parent: http_request (SPAN_KIND_CLIENT) - from CronJob
  └─ Child: GET / (SPAN_KIND_SERVER) - from Spring Boot app
```

## Troubleshooting

**No CronJob found:**
Wait 1-2 minutes for the CronJob to execute (runs every minute), or manually trigger:
```bash
kubectl create job --from=cronjob/request-sender manual-test -n my-demo
```

**Trace not found in Tempo:**
- Check Tempo pod logs: `kubectl logs -n observability -l app.kubernetes.io/name=tempo`
- Verify OTel Collector is exporting: `kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-collector`
- Increase wait time (currently 5 seconds) if disk is slow

**Empty span count or services:**
- Verify port-forward to Tempo is active
- Check if jq is installed: `which jq`
- Manually query: `curl http://localhost:3100/api/traces/{trace_id} | jq`

## Manual Verification

If the script fails, manually verify each step:

```bash
# Get latest CronJob
latest_job=$(kubectl get jobs -n my-demo -l app=request-sender --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')

# Extract trace_id
trace_id=$(kubectl logs -n my-demo job/$latest_job | grep "Trace ID:" | awk '{print $NF}')

# Query Tempo
curl -s "http://localhost:3100/api/traces/$trace_id" | jq '.'

# Count spans
curl -s "http://localhost:3100/api/traces/$trace_id" | jq '[.batches[].scopeSpans[].spans[]] | length'

# Get services
curl -s "http://localhost:3100/api/traces/$trace_id" | jq -r '.batches[].resource.attributes[]? | select(.key=="service.name") | .value.stringValue'
```

## What Success Means

When the verification succeeds, you've confirmed:
- W3C trace context propagation works (traceparent header)
- OTel Collector receives spans from both applications
- OTel Collector exports spans to Tempo
- Tempo stores and indexes traces correctly
- Parent-child relationships are preserved
- End-to-end distributed tracing is functional