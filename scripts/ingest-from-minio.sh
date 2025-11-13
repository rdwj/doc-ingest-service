#!/bin/bash
# Ingest documents from MinIO to doc-ingest-service
# Wrapper script that finds the doc-ingest service URL and passes credentials

set -e

NAMESPACE=${1:-servicenow-ai-poc}

echo "📊 MinIO Document Ingestion"
echo "================================================"

# Get doc-ingest-service route
INGEST_URL=$(oc get route doc-ingest-service -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null)

if [ -z "$INGEST_URL" ]; then
    echo "❌ Could not find doc-ingest-service route in namespace $NAMESPACE"
    exit 1
fi

INGEST_URL="https://${INGEST_URL}/ingest"

echo "✅ Doc-ingest service URL: $INGEST_URL"
echo ""

# Check if required environment variables are set
MISSING_VARS=0

if [ -z "$MINIO_ENDPOINT" ]; then
    echo "⚠️  MINIO_ENDPOINT not set"
    MISSING_VARS=1
fi

if [ -z "$MINIO_ACCESS_KEY" ]; then
    echo "⚠️  MINIO_ACCESS_KEY not set"
    MISSING_VARS=1
fi

if [ -z "$MINIO_SECRET_KEY" ]; then
    echo "⚠️  MINIO_SECRET_KEY not set"
    MISSING_VARS=1
fi

if [ $MISSING_VARS -eq 1 ]; then
    echo ""
    echo "Please set the required environment variables:"
    echo "  export MINIO_ENDPOINT=https://your-minio-endpoint"
    echo "  export MINIO_ACCESS_KEY=your_access_key"
    echo "  export MINIO_SECRET_KEY=your_secret_key"
    echo ""
    echo "Optional:"
    echo "  export MINIO_BUCKET=kb-documents     # default: kb-documents"
    echo "  export MINIO_PREFIX=data/            # default: data/"
    echo ""
    exit 1
fi

# Check if Python script exists
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PYTHON_SCRIPT="$SCRIPT_DIR/ingest-from-minio.py"

if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "❌ Python script not found: $PYTHON_SCRIPT"
    exit 1
fi

# Check for Python dependencies
echo "Checking Python dependencies..."
if ! python3 -c "import boto3, requests" 2>/dev/null; then
    echo "⚠️  Missing dependencies. Installing..."
    pip3 install --user boto3 requests urllib3
fi

echo "✅ Dependencies ready"
echo ""

# Run the Python script with arguments
# Note: All arguments after namespace are passed to Python script
python3 "$PYTHON_SCRIPT" --ingest-url "$INGEST_URL" "${@:2}"
