#!/bin/bash
# Build and push minio-ingestion-job container

set -e

IMAGE_NAME="quay.io/wjackson/minio-ingestion-job"
TAG="${1:-latest}"

echo "🔨 Building MinIO Ingestion Job Container"
echo "==========================================="
echo "Image: ${IMAGE_NAME}:${TAG}"
echo ""

# Build from project root
cd "$(dirname "$0")/.."

echo "📦 Building container..."
podman build --platform linux/amd64 -t "${IMAGE_NAME}:${TAG}" -f job/Containerfile .

echo ""
echo "📤 Pushing to Quay..."
podman push "${IMAGE_NAME}:${TAG}"

echo ""
echo "==========================================="
echo "✅ Image pushed successfully!"
echo ""
echo "Image: ${IMAGE_NAME}:${TAG}"
echo ""
echo "Next steps:"
echo "  1. Edit job/secret.yaml with your MinIO credentials"
echo "  2. Run: ./job/run-ingestion.sh <namespace>"
