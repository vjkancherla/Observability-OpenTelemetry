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
