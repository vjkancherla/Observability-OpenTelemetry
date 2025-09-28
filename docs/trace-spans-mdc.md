# MDC (Mapped Diagnostic Context) Usage in Logback

## 📍 Where MDC is Configured in logback-spring.xml

### Current Configuration

```xml
<encoder class="net.logstash.logback.encoder.LogstashEncoder">
    <customFields>{"service":"tracing-webapp"}</customFields>
    <fieldNames>
        <timestamp>timestamp</timestamp>
        <message>message</message>
        <logger>logger</logger>
        <thread>thread</thread>
        <level>level</level>
    </fieldNames>
    <!-- ⭐ HERE: MDC keys are configured to be included in logs -->
    <includeMdcKeyName>trace_id</includeMdcKeyName>
    <includeMdcKeyName>span_id</includeMdcKeyName>
</encoder>
```

### What This Does

The `<includeMdcKeyName>` tags tell Logstash encoder to:
1. **Look for** MDC keys named `trace_id` and `span_id`
2. **Include them** in the JSON output if they exist
3. **Omit them** if they're not present (no null fields)

---

## 📝 Where MDC is Set in Your Controller

### In TracingController.java

```java
@GetMapping("/simulate-error")
public ResponseEntity<Map<String, Object>> simulateError(
        @RequestHeader(value = "traceparent", required = false) String traceparent) {
    
    String traceId = extractTraceId(traceparent);
    
    // ⭐ HERE: MDC is populated with trace_id
    if (traceId != null) {
        MDC.put("trace_id", traceId);  // <-- MDC.put()
    }
    
    // When you log, MDC values are automatically included
    logger.error("Simulated error - Database connection timeout");
    
    // ⭐ HERE: MDC is cleared after logging
    MDC.clear();  // <-- MDC.clear()
    
    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(response);
}
```

---

## 🔄 Complete MDC Flow

### Step 1: Request Arrives
```
CronJob → Spring Boot
Header: traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
```

### Step 2: Controller Extracts trace_id
```java
String traceId = extractTraceId(traceparent);
// traceId = "0af7651916cd43dd8448eb211c80319c"
```

### Step 3: MDC.put() Adds to Thread Context
```java
MDC.put("trace_id", traceId);
// MDC now contains: {trace_id: "0af7651916cd43dd8448eb211c80319c"}
```

### Step 4: Logger Uses MDC
```java
logger.error("Simulated error - Database connection timeout");
```

### Step 5: Logback Encoder Reads MDC
```xml
<!-- logback-spring.xml knows to look for trace_id -->
<includeMdcKeyName>trace_id</includeMdcKeyName>
```

### Step 6: JSON Output Includes MDC Values
```json
{
  "timestamp": "2025-01-15T10:30:45.123Z",
  "level": "ERROR",
  "service": "tracing-webapp",
  "message": "Simulated error - Database connection timeout",
  "trace_id": "0af7651916cd43dd8448eb211c80319c",  // ⭐ From MDC!
  "logger": "com.example.tracingapp.controller.TracingController",
  "thread": "http-nio-8080-exec-1"
}
```

### Step 7: MDC.clear() Removes from Context
```java
MDC.clear();  // Cleans up for next request
```

---

## 🤔 What If MDC is NOT Set?

### Scenario: Request without traceparent header

```bash
curl http://localhost:8080/simulate-error
# No traceparent header
```

**Result:**
```java
String traceId = extractTraceId(null);  // Returns null
if (traceId != null) {
    MDC.put("trace_id", traceId);  // ❌ Skipped!
}
```

**Log Output:**
```json
{
  "timestamp": "2025-01-15T10:30:45.123Z",
  "level": "ERROR",
  "service": "tracing-webapp",
  "message": "Simulated error - Database connection timeout",
  // ❌ No trace_id field (omitted when not in MDC)
  "logger": "com.example.tracingapp.controller.TracingController",
  "thread": "http-nio-8080-exec-1"
}
```

---

## 🔧 With OpenTelemetry Java Agent (Automatic MDC)

When using the OTel Java Agent, **you don't need manual MDC.put()** because:

### Agent Automatically Populates MDC

```java
// ❌ OLD: Manual MDC (your current code)
String traceId = extractTraceId(traceparent);
if (traceId != null) {
    MDC.put("trace_id", traceId);
}

// ✅ NEW: OTel Agent does this automatically!
// No code needed - agent injects trace_id and span_id into MDC
@GetMapping("/simulate-error")
public ResponseEntity<?> simulateError() {
    // Just log - agent already populated MDC!
    logger.error("Simulated error");
    return ResponseEntity.status(500).body(...);
}
```

### Logback Still Works the Same

```xml
<!-- Still configured in logback-spring.xml -->
<includeMdcKeyName>trace_id</includeMdcKeyName>
<includeMdcKeyName>span_id</includeMdcKeyName>
```

### Output with OTel Agent

```json
{
  "timestamp": "2025-01-15T10:30:45.123Z",
  "level": "ERROR",
  "service": "tracing-webapp",
  "message": "Simulated error",
  "trace_id": "0af7651916cd43dd8448eb211c80319c",  // ⭐ Auto-injected by agent
  "span_id": "c5f8a2d3e1b4f6a7",                  // ⭐ Auto-injected by agent
  "logger": "com.example.tracingapp.controller.TracingController"
}
```

---

## 📊 MDC Key Differences

| Aspect | Manual (Your Current Code) | With OTel Agent |
|--------|---------------------------|-----------------|
| **Code Needed** | `MDC.put()` and `MDC.clear()` | None - automatic |
| **trace_id Source** | Parse traceparent header | Agent extracts automatically |
| **span_id** | ❌ Not available | ✅ Automatically included |
| **Error Prone** | Must remember to clear MDC | No cleanup needed |
| **Thread Safety** | Must manage manually | Agent handles thread context |

---

## 🎯 Recommended: Remove Manual MDC with OTel Agent

### Before (Manual)
```java
@GetMapping("/simulate-error")
public ResponseEntity<?> simulateError(
        @RequestHeader(value = "traceparent", required = false) String traceparent) {
    
    String traceId = extractTraceId(traceparent);
    if (traceId != null) {
        MDC.put("trace_id", traceId);
    }
    
    logger.error("Simulated error");
    
    MDC.clear();  // Must remember to clean up!
    
    return ResponseEntity.status(500).body(...);
}
```

### After (With OTel Agent)
```java
@GetMapping("/simulate-error")
public ResponseEntity<?> simulateError() {
    // OTel Agent automatically:
    // - Extracts trace context
    // - Creates span
    // - Populates MDC with trace_id and span_id
    // - Cleans up after request
    
    logger.error("Simulated error");  // MDC already has trace_id!
    
    return ResponseEntity.status(500).body(...);
}
```

---

## 🔍 Verifying MDC in Logs

### Test Current Implementation
```bash
# With traceparent header
curl -H "traceparent: 00-abc123-def456-01" http://localhost:8080/simulate-error

# Check logs - should see:
# {"trace_id": "abc123", "message": "Simulated error", ...}
```

### Test with OTel Agent
```bash
# Run with agent
java -javaagent:otel/opentelemetry-javaagent.jar \
     -Dotel.service.name=tracing-webapp \
     -jar target/tracing-app-1.0.0.jar

# Make request (even without traceparent, agent creates new trace)
curl http://localhost:8080/simulate-error

# Check logs - should see:
# {"trace_id": "...", "span_id": "...", "message": "Simulated error", ...}
```

---

## 📝 Summary

### MDC Configuration Location
**File:** `src/main/resources/logback-spring.xml`
```xml
<includeMdcKeyName>trace_id</includeMdcKeyName>
<includeMdcKeyName>span_id</includeMdcKeyName>
```

### MDC Usage in Code
**File:** `TracingController.java`
```java
MDC.put("trace_id", traceId);   // Set
logger.error("message");        // Use (automatic)
MDC.clear();                    // Clean up
```

### With OTel Agent
- ✅ No manual `MDC.put()` needed
- ✅ No manual `MDC.clear()` needed
- ✅ Automatically includes `trace_id` and `span_id`
- ✅ Logback config stays the same