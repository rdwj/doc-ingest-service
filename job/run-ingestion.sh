#!/bin/bash
# Run MinIO ingestion job in OpenShift

set -e

NAMESPACE=${1:-servicenow-ai-poc}

echo "📊 Running MinIO Ingestion Job"
echo "========================================"
echo "Namespace: $NAMESPACE"
echo ""

# Check if secret exists
if ! oc get secret minio-credentials -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Secret 'minio-credentials' not found"
    echo ""
    echo "Create the secret with your MinIO credentials:"
    echo ""
    echo "  oc create secret generic minio-credentials \\"
    echo "    --from-literal=MINIO_ENDPOINT=https://your-minio-endpoint \\"
    echo "    --from-literal=MINIO_ACCESS_KEY=your_access_key \\"
    echo "    --from-literal=MINIO_SECRET_KEY=your_secret_key \\"
    echo "    --from-literal=MINIO_BUCKET=kb-documents \\"
    echo "    --from-literal=MINIO_PREFIX=data/ \\"
    echo "    -n $NAMESPACE"
    echo ""
    exit 1
fi

echo "✅ Found MinIO credentials secret"

# Delete old job if exists
if oc get job minio-ingestion -n "$NAMESPACE" >/dev/null 2>&1; then
    echo ""
    echo "🗑️  Deleting previous job..."
    oc delete job minio-ingestion -n "$NAMESPACE"
    sleep 2
fi

# Create job
echo ""
echo "🚀 Creating ingestion job..."
oc apply -f "$(dirname "$0")/ingestion-job.yaml" -n "$NAMESPACE"

echo ""
echo "⏳ Waiting for job to start..."
sleep 3

# Get pod name
POD_NAME=$(oc get pods -n "$NAMESPACE" -l app=minio-ingestion --field-selector=status.phase!=Succeeded,status.phase!=Failed -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    echo "⚠️  Job pod not found yet. Check manually:"
    echo "   oc get pods -n $NAMESPACE -l app=minio-ingestion"
    echo "   oc logs -f job/minio-ingestion -n $NAMESPACE"
    exit 0
fi

echo "✅ Job pod created: $POD_NAME"
echo ""
echo "📋 Following logs..."
echo "========================================"
oc logs -f "$POD_NAME" -n "$NAMESPACE"

# Check final status
echo ""
echo "========================================"
echo "📊 Job Status"
echo "========================================"
oc get job minio-ingestion -n "$NAMESPACE"

# Check if succeeded
if oc get job minio-ingestion -n "$NAMESPACE" -o jsonpath='{.status.succeeded}' | grep -q "1"; then
    echo ""
    echo "✅ Ingestion completed successfully!"
    exit 0
else
    echo ""
    echo "❌ Ingestion failed or incomplete"
    echo ""
    echo "Check logs:"
    echo "  oc logs job/minio-ingestion -n $NAMESPACE"
    exit 1
fi
