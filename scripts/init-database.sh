#!/bin/bash
# Initialize PostgreSQL database schema for tsvector full-text search

set -e

NAMESPACE=${1:-servicenow-ai-poc}

echo "📊 Initializing database schema for namespace: $NAMESPACE"
echo "============================================================"

# Check if PostgreSQL is running
if ! oc get statefulset postgres-pgvector -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ PostgreSQL not found in namespace $NAMESPACE"
    exit 1
fi

# Get PostgreSQL pod name
echo ""
echo "Finding PostgreSQL pod..."
POD_NAME=$(oc get pods -l app=postgres-pgvector -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    echo "❌ Could not find PostgreSQL pod"
    exit 1
fi

echo "✅ Found pod: $POD_NAME"

# Test connection
echo ""
echo "Testing database connection..."
if oc exec "$POD_NAME" -n "$NAMESPACE" -- psql -U raguser -d ragdb -c "SELECT 1" >/dev/null 2>&1; then
    echo "✅ Database connection successful"
else
    echo "❌ Database connection failed"
    echo "   Check that PostgreSQL is running and credentials are correct"
    exit 1
fi

# Create schema
echo ""
echo "Creating database schema..."
oc exec "$POD_NAME" -n "$NAMESPACE" -- psql -U raguser -d ragdb <<'EOF'
-- Create document_chunks table with tsvector for full-text search
CREATE TABLE IF NOT EXISTS document_chunks (
    id SERIAL PRIMARY KEY,
    text TEXT NOT NULL,
    text_search tsvector NOT NULL,
    document_uri TEXT NOT NULL,
    chunk_num INTEGER NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create GIN index for fast full-text search
CREATE INDEX IF NOT EXISTS idx_text_search_gin ON document_chunks USING GIN(text_search);

-- Create index on document_uri for filtering
CREATE INDEX IF NOT EXISTS idx_document_uri ON document_chunks(document_uri);

-- Create index on metadata for JSONB queries
CREATE INDEX IF NOT EXISTS idx_metadata_gin ON document_chunks USING GIN(metadata);

-- Create function to automatically update text_search on insert/update
CREATE OR REPLACE FUNCTION document_chunks_tsvector_update() RETURNS trigger AS $$
BEGIN
    NEW.text_search := to_tsvector('english', NEW.text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if exists (to avoid duplicate trigger errors)
DROP TRIGGER IF EXISTS tsvector_update ON document_chunks;

-- Create trigger to auto-update text_search
CREATE TRIGGER tsvector_update BEFORE INSERT OR UPDATE
ON document_chunks FOR EACH ROW
EXECUTE FUNCTION document_chunks_tsvector_update();

SELECT 'Schema created successfully' AS status;
EOF

if [ $? -eq 0 ]; then
    echo "✅ Schema created successfully"
else
    echo "❌ Schema creation failed"
    exit 1
fi

# Verify schema
echo ""
echo "Verifying schema..."
RESULT=$(oc exec "$POD_NAME" -n "$NAMESPACE" -- psql -U raguser -d ragdb -t -c "\dt document_chunks" 2>/dev/null)

if [ -n "$RESULT" ]; then
    echo "✅ Table 'document_chunks' exists"
else
    echo "❌ Table 'document_chunks' not found"
    exit 1
fi

# Show index count
INDEX_COUNT=$(oc exec "$POD_NAME" -n "$NAMESPACE" -- psql -U raguser -d ragdb -t -c "
    SELECT COUNT(*) FROM pg_indexes WHERE tablename = 'document_chunks';
" | tr -d ' ')

echo "✅ Created $INDEX_COUNT indexes"

echo ""
echo "============================================================"
echo "✅ Database initialization complete!"
echo ""
echo "The database is ready for document ingestion."
echo ""
echo "Next steps:"
echo "  1. Test ingestion: ./scripts/test-ingest.sh $NAMESPACE"
echo "  2. Run pipeline from data-pipeline repository"
