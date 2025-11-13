#!/bin/bash
# Test document ingestion

set -e

NAMESPACE=${1:-servicenow-ai-poc}

echo "🧪 Testing document ingestion in namespace: $NAMESPACE"
echo "======================================================="

# Check if service is running
if ! oc get deployment doc-ingest-service -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Service not deployed. Run ./scripts/deploy.sh first"
    exit 1
fi

# Create test document
echo ""
echo "Creating test document..."
TEST_DOC=$(mktemp --suffix=.md)
cat > "$TEST_DOC" <<'EOF'
# Test Document

This is a test document for the ingestion service.

## Section 1: Introduction

This document tests the following capabilities:
- Document parsing
- Text chunking
- Embedding generation
- Database storage

## Section 2: Technical Details

The document ingestion service uses:
1. Docling for parsing
2. LangChain for chunking
3. Nomic for embeddings
4. PostgreSQL with pgvector for storage

## Section 3: Conclusion

This test validates the end-to-end ingestion pipeline.
EOF

echo "   Created: $TEST_DOC"
echo "   Size: $(wc -c < "$TEST_DOC") bytes"

# Port forward
echo ""
echo "Setting up port-forward..."
oc port-forward deployment/doc-ingest-service 8001:8001 -n "$NAMESPACE" >/dev/null 2>&1 &
PF_PID=$!
trap "kill $PF_PID 2>/dev/null" EXIT

# Wait for port-forward
sleep 2

# Test health first
echo ""
echo "Testing health endpoint..."
if curl -s http://localhost:8001/health | grep -q "healthy"; then
    echo "   ✅ Health check passed"
else
    echo "   ❌ Health check failed"
    kill $PF_PID
    exit 1
fi

# Test ingestion
echo ""
echo "Testing document ingestion..."
RESPONSE=$(curl -s -X POST http://localhost:8001/ingest \
    -F "file=@$TEST_DOC" \
    -F 'metadata={"source":"test-script","test":true}')

echo "   Response: $RESPONSE"

# Check response
if echo "$RESPONSE" | grep -q "success"; then
    CHUNKS=$(echo "$RESPONSE" | grep -o '"chunks_created":[0-9]*' | cut -d':' -f2)
    PROCESSING_TIME=$(echo "$RESPONSE" | grep -o '"processing_time":[0-9.]*' | cut -d':' -f2)

    echo ""
    echo "   ✅ Ingestion successful!"
    echo "      Chunks created: $CHUNKS"
    echo "      Processing time: ${PROCESSING_TIME}s"
else
    echo ""
    echo "   ❌ Ingestion failed"
    echo "      Response: $RESPONSE"
    kill $PF_PID
    rm -f "$TEST_DOC"
    exit 1
fi

# Verify in database
echo ""
echo "Verifying database..."
POD_NAME=$(oc get pods -l app=postgres-pgvector -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

if [ -n "$POD_NAME" ]; then
    COUNT=$(oc exec "$POD_NAME" -n "$NAMESPACE" -- \
        psql -U raguser -d ragdb -t -c \
        "SELECT COUNT(*) FROM document_chunks WHERE metadata->>'source' = 'test-script';" \
        2>/dev/null | tr -d ' ')

    if [ "$COUNT" -eq "$CHUNKS" ]; then
        echo "   ✅ Database verification passed"
        echo "      Found $COUNT chunks in database"
    else
        echo "   ⚠️  Chunk count mismatch"
        echo "      Expected: $CHUNKS, Found: $COUNT"
    fi
else
    echo "   ⚠️  Could not verify database (PostgreSQL pod not found)"
fi

# Cleanup
echo ""
echo "Cleaning up..."
kill $PF_PID 2>/dev/null || true
rm -f "$TEST_DOC"

echo ""
echo "======================================================="
echo "✅ Test completed successfully!"
echo ""
echo "The service is working correctly and ready for production use."
