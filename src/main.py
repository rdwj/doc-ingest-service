"""
Simple Document Ingestion Service
Processes documents and stores them with PostgreSQL tsvector for full-text search (TF-IDF style)
"""
import os
import logging
from pathlib import Path
from typing import List, Dict, Any
import asyncpg
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from langchain_text_splitters import RecursiveCharacterTextSplitter

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Document Ingestion Service",
    description="Service for ingesting documents with PostgreSQL full-text search (tsvector)",
    version="2.0.0"
)

# Configuration from environment
DB_HOST = os.getenv("POSTGRES_HOST", "localhost")
DB_PORT = int(os.getenv("POSTGRES_PORT", "5432"))
DB_USER = os.getenv("POSTGRES_USER", "raguser")
DB_PASSWORD = os.getenv("POSTGRES_PASSWORD", "ragpassword")
DB_NAME = os.getenv("POSTGRES_DB", "ragdb")

CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "800"))
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "150"))


class IngestResponse(BaseModel):
    success: bool
    document_uri: str
    chunks_created: int
    message: str


def clean_text(text: str) -> str:
    """
    Clean text to handle encoding issues and PostgreSQL constraints
    - Remove null bytes (0x00) which PostgreSQL TEXT cannot store
    - Replace other problematic characters
    - Ensure valid UTF-8 encoding
    """
    # Remove null bytes
    text = text.replace('\x00', '')

    # Remove other control characters except newlines, tabs, and carriage returns
    import re
    text = re.sub(r'[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]', '', text)

    # Ensure valid UTF-8 by encoding and decoding with error handling
    text = text.encode('utf-8', errors='ignore').decode('utf-8')

    return text


async def chunk_text(text: str) -> List[Dict[str, Any]]:
    """Chunk text using RecursiveCharacterTextSplitter"""
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=CHUNK_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
        length_function=len,
        is_separator_regex=False,
    )

    chunks = splitter.split_text(text)

    return [
        {"text": chunk, "chunk_num": idx}
        for idx, chunk in enumerate(chunks)
    ]


async def insert_chunks(
    conn: asyncpg.Connection,
    chunks: List[Dict[str, Any]],
    document_uri: str,
    metadata: Dict[str, Any]
) -> int:
    """Insert chunks with tsvector for full-text search"""
    import json

    total_inserted = 0

    for chunk in chunks:
        try:
            # Convert metadata dict to JSON string
            metadata_json = json.dumps(metadata)

            # Insert chunk with tsvector generated automatically by PostgreSQL
            await conn.execute(
                """
                INSERT INTO document_chunks (text, text_search, document_uri, chunk_num, metadata)
                VALUES ($1, to_tsvector('english', $1), $2, $3, $4::jsonb)
                """,
                chunk["text"],
                document_uri,
                chunk["chunk_num"],
                metadata_json
            )
            total_inserted += 1
            logger.info(f"Inserted chunk {chunk['chunk_num']} for {document_uri}")

        except Exception as e:
            logger.error(f"Failed to insert chunk {chunk['chunk_num']}: {e}")
            # Continue with other chunks even if one fails
            continue

    return total_inserted


@app.get("/health")
async def health():
    """Health check endpoint"""
    # Test database connection
    try:
        conn = await asyncpg.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            database=DB_NAME,
            timeout=5.0
        )
        await conn.execute("SELECT 1")
        await conn.close()
        db_status = "connected"
    except Exception as e:
        logger.error(f"Database health check failed: {e}")
        db_status = "disconnected"

    return {
        "status": "healthy" if db_status == "connected" else "degraded",
        "database": db_status,
        "search_type": "postgresql_tsvector"
    }


@app.post("/ingest", response_model=IngestResponse)
async def ingest_document(
    file: UploadFile = File(None),
    document_uri: str = Form(None),
    text_content: str = Form(None),
    metadata: str = Form("{}")
):
    """
    Ingest a single document

    Can provide either:
    - file: Upload a file (MD, TXT, HTML)
    - document_uri: URI/path to process
    - text_content: Direct text content
    """
    import json

    if not any([file, document_uri, text_content]):
        raise HTTPException(400, "Must provide file, document_uri, or text_content")

    try:
        metadata_dict = json.loads(metadata)
    except:
        metadata_dict = {}

    # Get text content
    if text_content:
        text = clean_text(text_content)
        uri = document_uri or "direct_input"
    elif file:
        content = await file.read()

        # Support text files (MD, TXT, HTML)
        # TODO: Add Docling for PDF/DOCX processing
        if file.filename.endswith(('.md', '.txt', '.html')):
            text = content.decode('utf-8', errors='replace')
        else:
            raise HTTPException(400, f"Unsupported file type: {file.filename}")

        uri = file.filename
        metadata_dict["filename"] = file.filename
    else:
        # document_uri provided - for pipeline use
        # Assume file exists and is readable
        path = Path(document_uri)
        if not path.exists():
            raise HTTPException(404, f"File not found: {document_uri}")

        text = path.read_text(encoding='utf-8', errors='replace')
        uri = document_uri

    # Clean text to remove null bytes and handle encoding issues
    text = clean_text(text)

    logger.info(f"Processing document: {uri} ({len(text)} chars)")

    # Chunk the text
    chunks = await chunk_text(text)
    logger.info(f"Created {len(chunks)} chunks")

    # Connect to database
    conn = await asyncpg.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME
    )

    try:
        # Insert chunks with tsvector
        chunks_inserted = await insert_chunks(conn, chunks, uri, metadata_dict)

        return IngestResponse(
            success=True,
            document_uri=uri,
            chunks_created=chunks_inserted,
            message=f"Successfully ingested {chunks_inserted} chunks from {uri}"
        )

    except Exception as e:
        logger.error(f"Ingestion failed: {e}")
        raise HTTPException(500, f"Ingestion failed: {str(e)}")

    finally:
        await conn.close()


@app.post("/ingest/batch")
async def ingest_batch(document_uris: List[str]):
    """
    Ingest multiple documents (for pipeline use)
    Processes one at a time
    """
    results = []

    for uri in document_uris:
        try:
            # Call single ingest for each
            result = await ingest_document(document_uri=uri, metadata="{}")
            results.append({"uri": uri, "success": True, "chunks": result.chunks_created})
        except Exception as e:
            logger.error(f"Failed to ingest {uri}: {e}")
            results.append({"uri": uri, "success": False, "error": str(e)})

    success_count = sum(1 for r in results if r["success"])

    return {
        "total": len(document_uris),
        "successful": success_count,
        "failed": len(document_uris) - success_count,
        "results": results
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
