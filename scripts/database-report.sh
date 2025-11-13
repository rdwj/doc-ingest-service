#!/bin/bash
# Generate a report of the document_chunks database

set -e

NAMESPACE=${1:-servicenow-ai-poc}

echo "📊 Document Chunks Database Report"
echo "========================================================================"
echo "Namespace: $NAMESPACE"
echo ""

# Get pod name
POD_NAME=$(oc get pods -l app=postgres-pgvector -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    echo "❌ PostgreSQL pod not found"
    exit 1
fi

echo "✅ Connected to: $POD_NAME"
echo ""

# Total chunks
echo "========================================================================"
echo "📈 SUMMARY STATISTICS"
echo "========================================================================"
TOTAL=$(oc exec "$POD_NAME" -n "$NAMESPACE" -- psql -U raguser -d ragdb -t -c "
    SELECT COUNT(*) FROM document_chunks;
" | tr -d ' ')
echo "Total chunks: $TOTAL"

# Unique documents
UNIQUE_DOCS=$(oc exec "$POD_NAME" -n "$NAMESPACE" -- psql -U raguser -d ragdb -t -c "
    SELECT COUNT(DISTINCT document_uri) FROM document_chunks;
" | tr -d ' ')
echo "Unique documents: $UNIQUE_DOCS"

# Average chunks per document
if [ "$UNIQUE_DOCS" -gt 0 ]; then
    AVG_CHUNKS=$((TOTAL / UNIQUE_DOCS))
    echo "Average chunks per document: $AVG_CHUNKS"
fi

echo ""

# Top 10 documents by chunk count
echo "========================================================================"
echo "📚 TOP 10 DOCUMENTS (by chunk count)"
echo "========================================================================"
oc exec "$POD_NAME" -n "$NAMESPACE" -- psql -U raguser -d ragdb -c "
    SELECT
        document_uri,
        COUNT(*) as chunks,
        MAX(created_at)::date as ingested_date
    FROM document_chunks
    GROUP BY document_uri
    ORDER BY chunks DESC
    LIMIT 10;
"

echo ""

# Recent documents
echo "========================================================================"
echo "🕐 RECENTLY INGESTED DOCUMENTS"
echo "========================================================================"
oc exec "$POD_NAME" -n "$NAMESPACE" -- psql -U raguser -d ragdb -c "
    SELECT
        document_uri,
        COUNT(*) as chunks,
        MAX(created_at) as last_ingested
    FROM document_chunks
    GROUP BY document_uri
    ORDER BY MAX(created_at) DESC
    LIMIT 10;
"

echo ""

# Documents with few chunks (potential issues)
echo "========================================================================"
echo "⚠️  DOCUMENTS WITH FEWEST CHUNKS (potential issues)"
echo "========================================================================"
oc exec "$POD_NAME" -n "$NAMESPACE" -- psql -U raguser -d ragdb -c "
    SELECT
        document_uri,
        COUNT(*) as chunks
    FROM document_chunks
    GROUP BY document_uri
    ORDER BY chunks ASC
    LIMIT 10;
"

echo ""

# Metadata analysis
echo "========================================================================"
echo "🏷️  METADATA SUMMARY"
echo "========================================================================"
oc exec "$POD_NAME" -n "$NAMESPACE" -- psql -U raguser -d ragdb -c "
    SELECT
        metadata->>'source' as source,
        COUNT(DISTINCT document_uri) as documents,
        COUNT(*) as total_chunks
    FROM document_chunks
    WHERE metadata->>'source' IS NOT NULL
    GROUP BY metadata->>'source'
    ORDER BY total_chunks DESC;
"

echo ""

# Sample chunk
echo "========================================================================"
echo "📄 SAMPLE CHUNK (first chunk from database)"
echo "========================================================================"
oc exec "$POD_NAME" -n "$NAMESPACE" -- psql -U raguser -d ragdb -c "
    SELECT
        document_uri,
        chunk_num,
        LEFT(text, 200) || '...' as text_preview
    FROM document_chunks
    ORDER BY id
    LIMIT 1;
"

echo ""

# Index information
echo "========================================================================"
echo "🔍 INDEX INFORMATION"
echo "========================================================================"
oc exec "$POD_NAME" -n "$NAMESPACE" -- psql -U raguser -d ragdb -c "
    SELECT
        indexname,
        indexdef
    FROM pg_indexes
    WHERE tablename = 'document_chunks';
"

echo ""
echo "========================================================================"
echo "✅ Report complete!"
echo ""
echo "To query the database directly:"
echo "  oc exec $POD_NAME -n $NAMESPACE -- psql -U raguser -d ragdb"
