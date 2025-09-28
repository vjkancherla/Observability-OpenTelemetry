# Spring Boot Tracing Application

A Spring Boot application with OpenTelemetry tracing support for distributed observability.

## 🚀 Quick Start

### Prerequisites
- Java 17 or higher
- Maven 3.6+
- Docker (optional, for containerization)

### Build and Run

```bash
# Build the application
mvn clean package

# Run locally
java -jar target/tracing-app-1.0.0.jar

# Access the application
curl http://localhost:8080/
```

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
```bash
curl -H "traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01" \
     http://localhost:8080/

curl -H "traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01" \
     http://localhost:8080/simulate-error
```

### Expected Log Output (JSON)
```json
{
  "timestamp": "2025-01-15T10:30:45.123Z",
  "level": "INFO",
  "service": "tracing-webapp",
  "message": "Home endpoint accessed successfully",
  "trace_id": "0af7651916cd43dd8448eb211c80319c"
}
```

## 🐳 Docker

### Build Image
```bash
docker build -t tracing-app:1.0.0 .
```

### Run Container
```bash
docker run -p 8080:8080 tracing-app:1.0.0
```

## 🔧 Project Structure

```
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
```

## 🎯 Next Steps: OpenTelemetry Integration

### 1. Download OTel Java Agent
```bash
wget https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar \
     -O otel/opentelemetry-javaagent.jar
```

### 2. Run with OTel Agent, and log to Console
```bash
JAVA_TOOL_OPTIONS="-javaagent:otel/opentelemetry-javaagent.jar" \
OTEL_SERVICE_NAME="tracing-webapp" \
OTEL_TRACES_EXPORTER="logging" \
OTEL_METRICS_EXPORTER="logging" \
OTEL_LOGS_EXPORTER="logging" \
OTEL_METRIC_EXPORT_INTERVAL="15000" \
java -jar target/tracing-app-1.0.0.jar
```


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
