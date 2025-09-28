# How OpenTelemetry Spans Are Created in Spring Boot

## 🎯 Current State (Without OTel Agent)

Your current `TracingController` does **NOT create OTel spans**. It only:

```java
// ❌ No span creation - just parsing header
private String extractTraceId(String traceparent) {
    String[] parts = traceparent.split("-");
    return parts[1]; // Extract trace_id manually
}

// ❌ No span creation - just logging
MDC.put("trace_id", traceId);
logger.info("Home endpoint accessed");
```

**Result:** Logs have `trace_id`, but no spans are sent to OTel Collector.

---

## ✅ With OpenTelemetry Java Agent (Automatic Instrumentation)

### How It Works

When you run with the OTel Java Agent:

```bash
java -javaagent:otel/opentelemetry-javaagent.jar \
     -Dotel.service.name=tracing-webapp \
     -Dotel.exporter.otlp.endpoint=http://otel-collector:4317 \
     -jar target/tracing-app-1.0.0.jar
```

The agent **automatically instruments** your application at runtime:

### 1. **Incoming HTTP Request** (CronJob → Spring Boot)

```
CronJob sends:
  GET /simulate-error
  Header: traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01

↓

OTel Agent intercepts HTTP request:
  ✅ Extracts traceparent header
  ✅ Extracts trace_id: 0af7651916cd43dd8448eb211c80319c
  ✅ Extracts parent_span_id: b7ad6b7169203331
  ✅ Creates NEW child span:
     - trace_id: 0af7651916cd43dd8448eb211c80319c (inherited)
     - span_id: c5f8a2d3e1b4f6a7 (NEW)
     - parent_span_id: b7ad6b7169203331
     - span.kind: SERVER
     - http.method: GET
     - http.url: /simulate-error
     - http.status_code: 500

↓

Your Controller executes:
  @GetMapping("/simulate-error")
  public ResponseEntity<?> simulateError(...) {
      // Agent automatically tracks this execution
      logger.error("Simulated error");
      return ResponseEntity.status(500).body(...);
  }

↓

OTel Agent finalizes span:
  ✅ Sets span.status: ERROR (because HTTP 500)
  ✅ Sets span.end_time
  ✅ Exports span to OTel Collector via OTLP
  ✅ Injects trace_id into MDC for logs
```

### 2. **What Gets Automatically Instrumented**

The OTel Java Agent instruments:

| Component | What Gets Traced | Span Attributes |
|-----------|-----------------|-----------------|
| **HTTP Server** | All incoming requests | `http.method`, `http.url`, `http.status_code` |
| **Spring MVC** | Controller methods | `spring.controller`, `spring.method` |
| **Logback** | Log statements | `trace_id` injected into MDC |
| **Database** | JDBC queries | `db.statement`, `db.system` |
| **HTTP Client** | Outgoing requests | `http.url`, `http.method` |

### 3. **Span Hierarchy Created**

```
Trace ID: 0af7651916cd43dd8448eb211c80319c

├── Span 1 (from CronJob)
│   ├── span_id: b7ad6b7169203331
│   ├── span.kind: CLIENT
│   ├── http.method: GET
│   └── http.url: http://webapp/simulate-error
│
└── Span 2 (from Spring Boot) ← Created by OTel Agent!
    ├── span_id: c5f8a2d3e1b4f6a7
    ├── parent_span_id: b7ad6b7169203331
    ├── span.kind: SERVER
    ├── http.method: GET
    ├── http.url: /simulate-error
    ├── http.status_code: 500
    └── span.status: ERROR
```

---

## 🔧 Alternative: Manual Span Creation (SDK)

If you want **explicit control** over spans (not using the agent), use the OTel SDK:

### Add Dependency to pom.xml

```xml
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-api</artifactId>
    <version>1.36.0</version>
</dependency>
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-sdk</artifactId>
    <version>1.36.0</version>
</dependency>
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
    <version>1.36.0</version>
</dependency>
```

### Manual Span Creation Code

```java
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.propagation.TextMapGetter;

@RestController
public class TracingController {

    private final Tracer tracer = GlobalOpenTelemetry.getTracer("tracing-webapp");

    @GetMapping("/simulate-error")
    public ResponseEntity<?> simulateError(
            @RequestHeader(value = "traceparent", required = false) String traceparent) {
        
        // Extract context from traceparent header
        Context extractedContext = extractContext(traceparent);
        
        // Create span with extracted parent context
        Span span = tracer.spanBuilder("simulate-error-handler")
                .setParent(extractedContext)
                .setSpanKind(SpanKind.SERVER)
                .setAttribute("http.method", "GET")
                .setAttribute("http.url", "/simulate-error")
                .startSpan();
        
        try {
            // Your business logic
            logger.error("Simulated error");
            
            // Set span attributes
            span.setAttribute("http.status_code", 500);
            span.setStatus(StatusCode.ERROR, "Simulated error");
            
            return ResponseEntity.status(500).body(...);
            
        } finally {
            span.end(); // Always end the span
        }
    }
}
```

**Problem with manual SDK:** You have to manually instrument EVERYTHING (DB calls, HTTP clients, etc.)

---

## 📊 Span Flow Comparison

### Current (No OTel Agent)
```
CronJob → Spring Boot
  ❌ No spans created in Spring Boot
  ✅ trace_id in logs only
  ❌ No trace visualization in Grafana
```

### With OTel Agent (Recommended)
```
CronJob → Spring Boot
  ✅ Parent span from CronJob
  ✅ Child span automatically created by agent
  ✅ trace_id in logs
  ✅ Full trace visualization in Grafana Tempo
  ✅ Metrics with trace_id (Span Metrics Connector)
```

---

## 🎯 Recommended Approach for Your Stack

**Use OpenTelemetry Java Agent** because:

1. ✅ **Zero code changes** - Automatic instrumentation
2. ✅ **Comprehensive** - Instruments HTTP, DB, logs, etc.
3. ✅ **W3C compliant** - Properly propagates trace context
4. ✅ **MDC injection** - Automatically adds trace_id to logs
5. ✅ **Works with design** - Integrates with Span Metrics Connector

### Updated Dockerfile with OTel Agent

```dockerfile
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# Copy application JAR
COPY target/tracing-app-1.0.0.jar app.jar

# Download OTel Java Agent
ADD https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar \
    /app/otel/opentelemetry-javaagent.jar

EXPOSE 8080

# Run with OTel agent
ENTRYPOINT ["java", \
            "-javaagent:/app/otel/opentelemetry-javaagent.jar", \
            "-jar", "/app/app.jar"]
```

### Environment Variables (Kubernetes)

```yaml
env:
  - name: OTEL_SERVICE_NAME
    value: "tracing-webapp"
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector:4317"
  - name: OTEL_TRACES_EXPORTER
    value: "otlp"
  - name: OTEL_METRICS_EXPORTER
    value: "otlp"
  - name: OTEL_LOGS_EXPORTER
    value: "otlp"
  - name: OTEL_PROPAGATORS
    value: "tracecontext,baggage"
```

---

## 🔍 Verifying Span Creation

### 1. Check Logs (MDC should have trace_id)
```json
{
  "timestamp": "2025-01-15T10:30:45.123Z",
  "level": "ERROR",
  "service": "tracing-webapp",
  "message": "Simulated error - Database connection timeout",
  "trace_id": "0af7651916cd43dd8448eb211c80319c",
  "span_id": "c5f8a2d3e1b4f6a7"
}
```

### 2. Check OTel Collector (should receive spans)
```bash
kubectl logs -n observability otel-collector-xxxx | grep "0af7651916cd43dd8448eb211c80319c"
```

### 3. Check Grafana Tempo (should show trace)
```
Query: trace_id = 0af7651916cd43dd8448eb211c80319c
```

---

## 📝 Summary

| Method | Code Changes | Completeness | Recommended |
|--------|--------------|--------------|-------------|
| **Current (none)** | ❌ Manual trace_id only | Logs only | ❌ No |
| **OTel Java Agent** | ✅ Zero changes | Complete auto-instrumentation | ✅ **YES** |
| **Manual SDK** | ❌ Lots of code | Partial (you must code everything) | ❌ No |

**Your Spring Boot app needs the OTel Java Agent to create spans automatically!**