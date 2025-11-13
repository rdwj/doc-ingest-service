# Database Schema for TF-IDF Full-Text Search

## Overview

The doc-ingest-service uses PostgreSQL's built-in full-text search with `tsvector` for TF-IDF-style document retrieval.

**No pgvector extension required!** This uses standard PostgreSQL features.

## Schema Definition

```sql
-- Create database (if not exists)
CREATE DATABASE ragdb;

-- Connect to database
\c ragdb;

-- Create document_chunks table with tsvector for full-text search
CREATE TABLE IF NOT EXISTS document_chunks (
    id SERIAL PRIMARY KEY,
    text TEXT NOT NULL,
    text_search tsvector NOT NULL,  -- TF-IDF search vector
    document_uri TEXT NOT NULL,
    chunk_num INTEGER NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create GIN index for fast full-text search
CREATE INDEX idx_text_search_gin ON document_chunks USING GIN(text_search);

-- Optional: Create index on document_uri for filtering
CREATE INDEX idx_document_uri ON document_chunks(document_uri);

-- Optional: Create index on metadata for JSONB queries
CREATE INDEX idx_metadata_gin ON document_chunks USING GIN(metadata);

-- Create function to automatically update text_search on insert/update
CREATE OR REPLACE FUNCTION document_chunks_tsvector_update() RETURNS trigger AS $$
BEGIN
    NEW.text_search := to_tsvector('english', NEW.text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to auto-update text_search
CREATE TRIGGER tsvector_update BEFORE INSERT OR UPDATE
ON document_chunks FOR EACH ROW
EXECUTE FUNCTION document_chunks_tsvector_update();
```

## How It Works

### 1. Text Storage
- `text`: Original chunk text
- `text_search`: PostgreSQL tsvector (tokenized, stemmed, with positions)

### 2. Full-Text Search (TF-IDF)
PostgreSQL's tsvector implements TF-IDF scoring automatically:
- **Term Frequency (TF)**: How often a term appears in a document
- **Inverse Document Frequency (IDF)**: How rare a term is across all documents
- **Ranking**: `ts_rank` and `ts_rank_cd` functions provide relevance scores

### 3. Search Query Example

```sql
-- Search for documents about "VNC connection troubleshooting"
SELECT
    document_uri,
    chunk_num,
    text,
    ts_rank(text_search, query) AS rank
FROM
    document_chunks,
    to_tsquery('english', 'VNC & connection & troubleshooting') AS query
WHERE
    text_search @@ query
ORDER BY
    rank DESC
LIMIT 10;
```

### 4. Advanced Search Examples

**Boolean operators:**
```sql
-- AND: VNC AND connection
to_tsquery('english', 'VNC & connection')

-- OR: VNC OR RealVNC
to_tsquery('english', 'VNC | RealVNC')

-- NOT: VNC but NOT Windows
to_tsquery('english', 'VNC & !Windows')

-- Phrase: "connection refused"
to_tsquery('english', 'connection <-> refused')
```

**Fuzzy matching:**
```sql
-- Use websearch_to_tsquery for natural language queries
SELECT * FROM document_chunks
WHERE text_search @@ websearch_to_tsquery('english', 'how to fix VNC connection issues')
ORDER BY ts_rank(text_search, websearch_to_tsquery('english', 'how to fix VNC connection issues')) DESC;
```

## Performance Characteristics

### Speed
- **GIN Index**: Very fast searches (milliseconds for millions of rows)
- **No external API calls**: All processing done in PostgreSQL
- **Concurrent queries**: PostgreSQL handles hundreds of concurrent searches

### Storage
- **tsvector size**: ~30-50% of original text size
- **GIN index**: ~50-100% additional overhead
- **Example**: 1000 documents (1MB total) = ~2-2.5MB database size

## Deployment Script

Create the schema during deployment:

```bash
#!/bin/bash
# scripts/init-database.sh

NAMESPACE=${1:-servicenow-ai-poc}

echo "Initializing database schema..."

# Port-forward to PostgreSQL
oc port-forward deployment/postgres-pgvector 5432:5432 -n "$NAMESPACE" &
PF_PID=$!
trap "kill $PF_PID" EXIT

sleep 2

# Get database password
DB_PASSWORD=$(oc get secret postgres-pgvector-secret -n "$NAMESPACE" \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)

# Create schema
PGPASSWORD="$DB_PASSWORD" psql -h localhost -U raguser -d ragdb <<EOF
-- Create table
CREATE TABLE IF NOT EXISTS document_chunks (
    id SERIAL PRIMARY KEY,
    text TEXT NOT NULL,
    text_search tsvector NOT NULL,
    document_uri TEXT NOT NULL,
    chunk_num INTEGER NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_text_search_gin ON document_chunks USING GIN(text_search);
CREATE INDEX IF NOT EXISTS idx_document_uri ON document_chunks(document_uri);
CREATE INDEX IF NOT EXISTS idx_metadata_gin ON document_chunks USING GIN(metadata);

-- Create trigger function
CREATE OR REPLACE FUNCTION document_chunks_tsvector_update() RETURNS trigger AS \$\$
BEGIN
    NEW.text_search := to_tsvector('english', NEW.text);
    RETURN NEW;
END;
\$\$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS tsvector_update ON document_chunks;
CREATE TRIGGER tsvector_update BEFORE INSERT OR UPDATE
ON document_chunks FOR EACH ROW
EXECUTE FUNCTION document_chunks_tsvector_update();

SELECT 'Schema created successfully' AS status;
EOF

echo "✅ Database schema initialized"
```

## Verification Queries

```sql
-- Check table exists
\dt document_chunks

-- Check indexes
\di

-- View sample data
SELECT id, document_uri, chunk_num, LEFT(text, 50) AS preview
FROM document_chunks
LIMIT 5;

-- Check tsvector content
SELECT document_uri, text_search
FROM document_chunks
LIMIT 1;

-- Test search
SELECT COUNT(*) AS matching_chunks
FROM document_chunks
WHERE text_search @@ to_tsquery('english', 'troubleshooting');
```

## Migration from pgvector (if needed)

If you have existing data with embeddings, you can migrate:

```sql
-- Add tsvector column to existing table
ALTER TABLE document_chunks ADD COLUMN text_search tsvector;

-- Populate tsvector from text
UPDATE document_chunks SET text_search = to_tsvector('english', text);

-- Create index
CREATE INDEX idx_text_search_gin ON document_chunks USING GIN(text_search);

-- Optional: Drop embedding column if no longer needed
-- ALTER TABLE document_chunks DROP COLUMN embedding;
```

## Advantages of tsvector

✅ **No external dependencies**: Everything in PostgreSQL
✅ **Fast**: GIN index provides sub-millisecond searches
✅ **Simple**: No API keys, no external services
✅ **Cost-effective**: No per-request charges
✅ **Scalable**: Handles millions of documents
✅ **Multilingual**: Supports many languages (english, spanish, french, etc.)
✅ **Proven**: Used in production by thousands of applications

## Disadvantages vs. Vector Embeddings

❌ **Semantic understanding**: tsvector is keyword-based (no synonyms)
❌ **Similarity threshold**: Harder to set relevance cutoffs
❌ **Cross-lingual**: Doesn't work across languages
❌ **Context**: Doesn't understand context like embeddings

For most technical documentation and FAQ retrieval, **tsvector is sufficient and much simpler**.

## References

- [PostgreSQL Full-Text Search Documentation](https://www.postgresql.org/docs/current/textsearch.html)
- [GIN Indexes](https://www.postgresql.org/docs/current/gin.html)
- [Text Search Functions](https://www.postgresql.org/docs/current/functions-textsearch.html)
