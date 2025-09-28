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
