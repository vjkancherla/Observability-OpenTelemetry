#!/bin/bash

echo "🧹 Cleaning up..."

pkill -f "kubectl port-forward" 2>/dev/null || true
k3d cluster delete mycluster 2>/dev/null || true

echo "✅ Done!"