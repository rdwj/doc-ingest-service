#!/usr/bin/env python3
"""
Ingest documents from MinIO to doc-ingest-service
"""
import os
import sys
import boto3
import requests
from pathlib import Path
from typing import List
import argparse
from botocore.client import Config

def get_minio_client(endpoint: str, access_key: str, secret_key: str):
    """Create MinIO/S3 client"""
    return boto3.client(
        's3',
        endpoint_url=endpoint,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(signature_version='s3v4'),
        verify=False  # Set to True in production with proper certs
    )

def list_documents(client, bucket: str, prefix: str = "data/") -> List[str]:
    """List all documents in MinIO bucket"""
    print(f"\n📂 Listing documents in bucket '{bucket}' with prefix '{prefix}'...")

    try:
        response = client.list_objects_v2(Bucket=bucket, Prefix=prefix)

        if 'Contents' not in response:
            print(f"⚠️  No files found in {bucket}/{prefix}")
            return []

        files = []
        for obj in response['Contents']:
            key = obj['Key']
            # Skip directories
            if not key.endswith('/'):
                files.append(key)

        print(f"✅ Found {len(files)} files")
        return files

    except Exception as e:
        print(f"❌ Error listing files: {e}")
        return []

def ingest_document(
    client,
    bucket: str,
    key: str,
    ingest_url: str
) -> bool:
    """Download document from MinIO and ingest to doc-ingest-service"""

    try:
        # Download from MinIO
        print(f"\n📥 Processing: {key}")
        obj = client.get_object(Bucket=bucket, Key=key)
        content = obj['Body'].read()

        # Get filename
        filename = Path(key).name

        # Prepare metadata
        metadata = {
            "source": "minio",
            "bucket": bucket,
            "original_path": key
        }

        # Post to doc-ingest-service
        files = {'file': (filename, content)}
        data = {'metadata': str(metadata).replace("'", '"')}

        response = requests.post(
            ingest_url,
            files=files,
            data=data,
            verify=False  # Set to True in production
        )

        if response.status_code == 200:
            result = response.json()
            print(f"   ✅ Ingested: {result.get('chunks_created', 0)} chunks")
            return True
        else:
            print(f"   ❌ Failed: {response.status_code} - {response.text}")
            return False

    except Exception as e:
        print(f"   ❌ Error: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(
        description='Ingest documents from MinIO to doc-ingest-service',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment Variables:
  MINIO_ENDPOINT     MinIO API endpoint URL
  MINIO_ACCESS_KEY   MinIO access key
  MINIO_SECRET_KEY   MinIO secret key
  MINIO_BUCKET       MinIO bucket name (default: kb-documents)
  MINIO_PREFIX       Path prefix in bucket (default: data/)

Examples:
  # Using environment variables
  export MINIO_ENDPOINT=https://minio.example.com
  export MINIO_ACCESS_KEY=mykey
  export MINIO_SECRET_KEY=mysecret
  %(prog)s --ingest-url https://ingest.example.com/ingest

  # Using command-line arguments
  %(prog)s --minio-endpoint https://minio.example.com \\
           --access-key mykey --secret-key mysecret \\
           --ingest-url https://ingest.example.com/ingest

  # Dry run to list files
  %(prog)s --dry-run --ingest-url https://ingest.example.com/ingest
        """
    )
    parser.add_argument(
        '--minio-endpoint',
        default=os.getenv('MINIO_ENDPOINT'),
        help='MinIO API endpoint URL (or set MINIO_ENDPOINT env var)'
    )
    parser.add_argument(
        '--bucket',
        default=os.getenv('MINIO_BUCKET', 'kb-documents'),
        help='MinIO bucket name (or set MINIO_BUCKET env var)'
    )
    parser.add_argument(
        '--prefix',
        default=os.getenv('MINIO_PREFIX', 'data/'),
        help='Path prefix in bucket (or set MINIO_PREFIX env var)'
    )
    parser.add_argument(
        '--ingest-url',
        required=True,
        help='Doc ingest service URL'
    )
    parser.add_argument(
        '--access-key',
        default=os.getenv('MINIO_ACCESS_KEY'),
        help='MinIO access key (or set MINIO_ACCESS_KEY env var)'
    )
    parser.add_argument(
        '--secret-key',
        default=os.getenv('MINIO_SECRET_KEY'),
        help='MinIO secret key (or set MINIO_SECRET_KEY env var)'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='List files without ingesting'
    )
    parser.add_argument(
        '--limit',
        type=int,
        help='Limit number of files to process'
    )

    args = parser.parse_args()

    # Validate required parameters
    if not args.minio_endpoint:
        print("❌ Error: MinIO endpoint is required")
        print("   Set MINIO_ENDPOINT env var or use --minio-endpoint")
        sys.exit(1)

    if not args.access_key:
        print("❌ Error: MinIO access key is required")
        print("   Set MINIO_ACCESS_KEY env var or use --access-key")
        sys.exit(1)

    if not args.secret_key:
        print("❌ Error: MinIO secret key is required")
        print("   Set MINIO_SECRET_KEY env var or use --secret-key")
        sys.exit(1)

    print("=" * 70)
    print("📊 MinIO to Doc-Ingest Service Pipeline")
    print("=" * 70)
    print(f"MinIO Endpoint: {args.minio_endpoint}")
    print(f"Bucket: {args.bucket}")
    print(f"Prefix: {args.prefix}")
    print(f"Ingest URL: {args.ingest_url}")
    print(f"Dry Run: {args.dry_run}")

    # Create MinIO client
    try:
        client = get_minio_client(
            args.minio_endpoint,
            args.access_key,
            args.secret_key
        )
    except Exception as e:
        print(f"❌ Failed to connect to MinIO: {e}")
        sys.exit(1)

    # List documents
    files = list_documents(client, args.bucket, args.prefix)

    if not files:
        print("\n⚠️  No files to process")
        sys.exit(0)

    # Apply limit if specified
    if args.limit:
        files = files[:args.limit]
        print(f"\n📌 Limited to {args.limit} files")

    if args.dry_run:
        print("\n🔍 Dry run - files found:")
        for f in files:
            print(f"   - {f}")
        print("\n✅ Dry run complete")
        sys.exit(0)

    # Ingest documents
    print("\n" + "=" * 70)
    print("📤 Starting ingestion...")
    print("=" * 70)

    success_count = 0
    fail_count = 0

    for idx, key in enumerate(files, 1):
        print(f"\n[{idx}/{len(files)}]", end=" ")

        if ingest_document(client, args.bucket, key, args.ingest_url):
            success_count += 1
        else:
            fail_count += 1

    # Summary
    print("\n" + "=" * 70)
    print("📊 Ingestion Summary")
    print("=" * 70)
    print(f"Total files: {len(files)}")
    print(f"✅ Successful: {success_count}")
    print(f"❌ Failed: {fail_count}")
    print("=" * 70)

    if fail_count > 0:
        sys.exit(1)

    print("\n✅ Ingestion complete!")

if __name__ == '__main__':
    main()
