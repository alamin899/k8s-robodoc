#!/bin/bash

echo "Applying Kubernetes configurations..."
kubectl apply -k .

echo "Restarting OpenTelemetry Collector deployment..."
kubectl rollout restart deployment/otel-collector -n opentelemetry

echo "Deployment complete."