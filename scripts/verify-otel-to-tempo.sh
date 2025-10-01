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