# OpenTelemetry-Based Observability Stack Design

## 🎯 Project Overview

**Problem**: When CronJob fails, need to quickly find related logs/traces

**Solution**: 
1. OpenTelemetry automatically generates trace_id
2. OTel Collector's Span Metrics Connector creates metrics with trace_id
3. Prometheus alert fires with trace_id
4. Alert contains direct links to Grafana filtered by trace_id
5. **One click → Complete distributed trace + filtered logs**

**Result**: Same alerting workflow as current stack (https://github.com/vjkancherla/Observability-Demo), but with distributed tracing visualization and richer context!

This document describes the design for an OpenTelemetry-native observability stack that demonstrates distributed tracing, correlation-based alerting, and unified observability across traces, metrics, and logs.

### Key Objectives
1. **Distributed Tracing**: Track requests across CronJob and Spring Boot webapp using W3C Trace Context
2. **Correlation-Based Alerting**: When CronJob fails, alert contains `trace_id` with direct links to traces and logs
3. **Unified Observability**: Single trace_id links traces (Tempo), metrics (Prometheus), and logs (Loki)
4. **Standards Compliance**: Use OpenTelemetry (CNCF standard) and W3C Trace Context

---

## 🏗️ Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Application Layer                                │
│                                                                       │
│  ┌──────────────┐           HTTP + traceparent       ┌─────────────┐│
│  │   CronJob    │─────────────────────────────────►  │ Spring Boot ││
│  │              │                                     │   Webapp    ││
│  │ OTel SDK     │                                     │ OTel Agent  ││
│  │ (manual)     │                                     │ (auto)      ││
│  └──────┬───────┘                                     └──────┬──────┘│
│         │                                                    │        │
│         │ OTLP                                              │ OTLP   │
│         │ (traces/metrics/logs)                             │        │
└─────────┼────────────────────────────────────────────────────┼───────┘
          │                                                    │
          └────────────────────┬───────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│              OpenTelemetry Collector (Central Pipeline)              │
│                                                                       │
│  ┌─────────────┐    ┌──────────────────┐    ┌───────────────────┐  │
│  │  Receivers  │───►│   Processors     │───►│    Exporters      │  │
│  │             │    │                  │    │                   │  │
│  │ - OTLP gRPC │    │ - Batch          │    │ - Tempo (traces)  │  │
│  │ - OTLP HTTP │    │ - Resource       │    │ - Prometheus      │  │
│  └─────────────┘    │ - Attributes     │    │   (metrics)       │  │
│                     └──────────────────┘    │ - Loki (logs)     │  │
│                                              └───────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Span Metrics Connector (Key Component!)                     │  │
│  │  - Generates metrics FROM spans in real-time                 │  │
│  │  - Includes trace_id as exemplar in metrics                  │  │
│  │  - Output: http_requests_total{trace_id="..."}               │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
          │                      │                        │
          ▼                      ▼                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Storage & Query Layer                             │
│                                                                       │
│  ┌──────────┐         ┌──────────────┐         ┌────────────────┐  │
│  │  Tempo   │         │  Prometheus  │         │     Loki       │  │
│  │          │         │              │         │                │  │
│  │ Traces   │◄────────┤  Metrics     │◄────────┤    Logs        │  │
│  │ (TraceQL)│  linked │  (PromQL)    │  linked │   (LogQL)      │  │
│  └──────────┘  by     └──────┬───────┘  by     └────────────────┘  │
│                trace_id       │          trace_id                    │
└───────────────────────────────┼──────────────────────────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  Alerting Layer                                      │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  PrometheusRule                                               │  │
│  │  - Query: http_requests_total{status="error"} > 0            │  │
│  │  - Labels include: trace_id                                  │  │
│  │  - Annotations include: trace_url, logs_url                  │  │
│  └──────────────────────┬───────────────────────────────────────┘  │
│                         ▼                                            │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  AlertManager                                                 │  │
│  │  - Receives alert with trace_id                              │  │
│  │  - Routes to webhook with clickable links                    │  │
│  └──────────────────────┬───────────────────────────────────────┘  │
└────────────────────────┼──────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  Visualization Layer                                 │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Grafana                                                      │  │
│  │  - Traces Dashboard (Tempo datasource)                       │  │
│  │  - Logs Dashboard (Loki datasource)                          │  │
│  │  - Metrics Dashboard (Prometheus datasource)                 │  │
│  │  - Automatic correlation by trace_id                         │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🔄 End-to-End Flow

### 1. Request Initiation (CronJob)
```
CronJob generates trace context:
├─ trace_id: "0af7651916cd43dd8448eb211c80319c" (32 hex chars)
├─ span_id: "b7ad6b7169203331" (16 hex chars)
└─ Creates W3C Traceparent header: "00-{trace_id}-{span_id}-01"

HTTP Request:
├─ Header: traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
└─ Target: http://webapp/simulate-error

Span Export:
└─ Exports span to OTel Collector via OTLP
```

### 2. Request Processing (Spring Boot)
```
OpenTelemetry Java Agent (automatic):
├─ Extracts traceparent from HTTP headers
├─ Extracts trace_id: "0af7651916cd43dd8448eb211c80319c"
├─ Creates child span with new span_id
├─ Injects trace_id into logs (MDC)
├─ Processes request → Returns HTTP 500
├─ Sets span status: ERROR
└─ Exports span to OTel Collector via OTLP
```

### 3. Telemetry Collection (OTel Collector)
```
Receives spans from both CronJob and Spring Boot

Span Metrics Connector generates metrics:
├─ Input: Span{trace_id="0af765...", status=ERROR}
└─ Output: http_requests_total{
             service="cronjob",
             status="error",
             trace_id="0af765..."  ← Key: trace_id as exemplar!
           } = 1

Routes telemetry:
├─ Spans → Tempo (trace storage)
├─ Generated Metrics → Prometheus (with trace_id)
└─ Logs → Loki (with trace_id)
```

### 4. Alert Detection (Prometheus)
```
PrometheusRule evaluates:
expr: http_requests_total{service="cronjob", status="error"} > 0

Metric found with:
├─ service="cronjob"
├─ status="error"
├─ trace_id="0af7651916cd43dd8448eb211c80319c"
└─ value=1

Alert fires with:
├─ Labels: {trace_id: "0af765..."}
└─ Annotations: {
     trace_url: "http://localhost:3000/explore?trace_id=0af765...",
     logs_url: "http://localhost:3000/explore?trace_id=0af765..."
   }
```

### 5. Alert Notification (AlertManager)
```
AlertManager receives alert

Webhook payload:
{
  "alerts": [{
    "labels": {
      "alertname": "CronJobFailed",
      "trace_id": "0af7651916cd43dd8448eb211c80319c"
    },
    "annotations": {
      "trace_url": "http://localhost:3000/explore?...",
      "logs_url": "http://localhost:3000/explore?..."
    }
  }]
}

User clicks trace_url:
└─ Grafana opens with trace visualization showing:
   ├─ CronJob span (parent)
   ├─ HTTP request span
   └─ Spring Boot span (child) with ERROR status
   
User can click "View Logs" in Grafana:
└─ Automatically filters logs by trace_id
```

---

## 🧩 Component Details

### Application Components

#### **CronJob (Sender)**
- **Technology**: Bash/Python/Go with OTel SDK
- **Responsibilities**:
  - Generate W3C trace context (trace_id, span_id)
  - Make HTTP request with `traceparent` header
  - Create and export span to OTel Collector
  - Handle errors (HTTP 500 = span status ERROR)

#### **Spring Boot Webapp**
- **Technology**: Spring Boot 3.2+ with OTel Java Agent
- **Instrumentation**: Automatic (zero-code via agent)
- **Responsibilities**:
  - Extract trace context from incoming request
  - Create child span automatically
  - Inject trace_id into logs (MDC)
  - Export span to OTel Collector
  - Endpoints:
    - `GET /` → Success (HTTP 200)
    - `GET /simulate-error` → Failure (HTTP 500)
    - `GET /health` → Health check

### Observability Components

#### **OpenTelemetry Collector**
- **Purpose**: Central telemetry pipeline
- **Key Feature**: Span Metrics Connector
  - Generates metrics from spans in real-time
  - Includes trace_id as exemplar in metrics
  - No Pushgateway needed!
- **Receivers**: OTLP (gRPC + HTTP)
- **Processors**: Batch, Resource, Attributes
- **Exporters**: Tempo, Prometheus, Loki

#### **Tempo**
- **Purpose**: Distributed tracing backend
- **Query Language**: TraceQL
- **Storage**: Local filesystem (PoC), S3/GCS (production)
- **Features**: 
  - Stores complete trace hierarchies
  - Automatic trace-to-logs linking in Grafana

#### **Prometheus**
- **Purpose**: Metrics storage and querying
- **Key Feature**: Exemplar support
  - Stores trace_id with metric samples
  - Enables click-through from metric to trace
- **Configuration**: 
  - Enable exemplar storage
  - Scrape OTel Collector metrics endpoint

#### **Loki**
- **Purpose**: Log aggregation
- **Log Source**: OTel Collector (not Promtail)
- **Key Feature**: Automatic trace_id extraction from logs
- **Configuration**:
  - Receive logs via OTel Collector's Loki exporter
  - Store with trace_id for correlation

#### **Grafana**
- **Purpose**: Unified visualization and correlation
- **Datasources**:
  - Tempo (traces)
  - Prometheus (metrics with exemplars)
  - Loki (logs with trace_id)
- **Key Features**:
  - Automatic trace-to-logs navigation
  - Automatic trace-to-metrics navigation
  - Pre-built dashboards with trace_id filters

#### **PrometheusRule + AlertManager**
- **Purpose**: Alerting on CronJob failures
- **Alert Rule**: Query span-generated metrics
- **Alert Payload**: Includes trace_id and Grafana URLs
- **Routing**: AlertManager sends to webhook with clickable links

---

## 🔑 Key Design Decisions

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| **Trace Propagation** | W3C Traceparent header | Industry standard, wide compatibility |
| **Spring Boot Instrumentation** | OTel Java Agent (auto) | Zero code changes, comprehensive coverage |
| **CronJob Instrumentation** | OTel SDK (manual) | Simple script, explicit control |
| **Metrics Generation** | Span Metrics Connector | Automatic metrics from spans, no Pushgateway |
| **Trace Storage** | Tempo | Purpose-built for traces, Grafana integration |
| **Alerting** | Prometheus + AlertManager | Familiar workflow, minimal changes from current |
| **Log Collection** | OTel Collector → Loki | Unified pipeline, automatic trace_id injection |
| **Correlation Key** | trace_id | OTel standard, links all telemetry types |

---

## 📊 Comparison with Current Stack

### Current Stack (nginx + Pushgateway)
```
CronJob → correlation_id → Pushgateway → Prometheus → Alert
                              ↓
Webapp → correlation_id in logs → Promtail → Loki

Alert contains: correlation_id + Grafana link to filtered logs
```

### New Stack (Spring Boot + OTel)
```
CronJob → trace_id → OTel Collector → Tempo (traces)
                          ↓
                     Span Metrics → Prometheus → Alert
                          ↓
Spring Boot → trace_id → OTel Collector → Loki (logs)

Alert contains: trace_id + Grafana links to traces AND logs
```

### Key Improvements
| Feature | Current | New (OTel) |
|---------|---------|-----------|
| **Context Propagation** | Manual correlation_id | Automatic W3C trace context |
| **Distributed Tracing** | ❌ None | ✅ Full trace visualization |
| **Timing Information** | ❌ None | ✅ Span durations |
| **Parent-Child Relationships** | ❌ None | ✅ Span hierarchy |
| **Alert Correlation** | ✅ correlation_id | ✅ trace_id (richer) |
| **Debugging Experience** | Logs only | Traces + Logs + Metrics |
| **Standards Compliance** | Custom | W3C + OTel (CNCF) |
| **Components** | 7 (includes Pushgateway, Promtail) | 6 (OTel Collector replaces both) |

---

## 🔍 Alert Flow Example

### Scenario: CronJob hits /simulate-error (HTTP 500)

**Step 1: Trace Generation**
```
trace_id: 0af7651916cd43dd8448eb211c80319c
CronJob span → Spring Boot span (child)
Both spans have status: ERROR
```

**Step 2: Metric Generation (Span Metrics Connector)**
```
http_requests_total{
  service="cronjob",
  status="error",
  trace_id="0af7651916cd43dd8448eb211c80319c"
} = 1
```

**Step 3: Alert Fires (PrometheusRule)**
```yaml
- alert: CronJobFailed
  expr: http_requests_total{service="cronjob", status="error"} > 0
  annotations:
    summary: "CronJob request failed"
    trace_id: "{{ $labels.trace_id }}"
    trace_url: "http://localhost:3000/explore?trace_id={{ $labels.trace_id }}"
    logs_url: "http://localhost:3000/explore?logs&trace_id={{ $labels.trace_id }}"
```

**Step 4: Webhook Receives Alert**
```json
{
  "alerts": [{
    "labels": {
      "trace_id": "0af7651916cd43dd8448eb211c80319c"
    },
    "annotations": {
      "trace_url": "http://localhost:3000/explore?trace_id=0af765...",
      "logs_url": "http://localhost:3000/explore?logs&trace_id=0af765..."
    }
  }]
}
```

**Step 5: User Clicks Link**
- **trace_url**: Opens Grafana showing full distributed trace with timing
- **logs_url**: Opens Grafana showing logs filtered to exact trace_id
- **One click**: Complete context for debugging

---

## 📋 Technology Stack

### Core Technologies
- **Container Orchestration**: k3d (k3s in Docker)
- **Application Runtime**: Java 17+ (Spring Boot 3.2+)
- **Observability Standard**: OpenTelemetry 1.x
- **Trace Context**: W3C Trace Context

### Observability Components
- **Telemetry Pipeline**: OpenTelemetry Collector 0.100+
- **Trace Backend**: Grafana Tempo 2.x
- **Metrics Backend**: Prometheus 2.x
- **Log Backend**: Grafana Loki 3.x
- **Visualization**: Grafana 11.x
- **Alerting**: PrometheusRule + AlertManager

### Instrumentation
- **Spring Boot**: OpenTelemetry Java Agent (auto-instrumentation)
- **CronJob**: OpenTelemetry SDK (manual instrumentation)
- **Log Format**: Structured JSON with trace_id

---

## ✅ Success Criteria

1. **Trace Propagation**: trace_id flows from CronJob → Spring Boot
2. **Automatic Correlation**: All telemetry (traces, metrics, logs) linked by trace_id
3. **Alert Contains trace_id**: PrometheusRule fires with trace_id in alert
4. **Clickable Links**: Webhook receives alert with Grafana URLs
5. **One-Click Debugging**: Click link → See trace + logs for exact request
6. **Visual Trace**: Grafana shows parent-child span relationships with timing
7. **Standards Compliance**: Uses W3C Trace Context and OTel standards

---

## 📚 References

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [W3C Trace Context](https://www.w3.org/TR/trace-context/)
- [Grafana Tempo](https://grafana.com/oss/tempo/)
- [OTel Collector Span Metrics](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/connector/spanmetricsconnector)
- [Prometheus Exemplars](https://prometheus.io/docs/prometheus/latest/feature_flags/#exemplars-storage)