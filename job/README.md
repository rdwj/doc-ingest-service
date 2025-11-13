# MinIO Ingestion Job

Kubernetes Job for ingesting documents from MinIO into the doc-ingest-service.

## Overview

This job runs a container that:
1. Connects to MinIO (S3-compatible storage)
2. Lists all documents in the specified bucket/prefix
3. Downloads each document
4. Posts it to the doc-ingest-service API

## Quick Start

### 1. Build and Push Container

From your local machine (with podman):

```bash
cd /path/to/doc-ingest-service
./job/build-and-push.sh
```

This builds the container image and pushes it to `quay.io/wjackson/minio-ingestion-job:latest`.

### 2. Create MinIO Credentials Secret

Create the secret with your actual MinIO credentials:

```bash
oc create secret generic minio-credentials \
  --from-literal=MINIO_ENDPOINT=https://your-minio-endpoint \
  --from-literal=MINIO_ACCESS_KEY=your_access_key \
  --from-literal=MINIO_SECRET_KEY=your_secret_key \
  --from-literal=MINIO_BUCKET=kb-documents \
  --from-literal=MINIO_PREFIX=data/ \
  -n servicenow-ai-poc
```

Replace the values with your actual MinIO credentials.

**Note**: `job/secret.yaml` is provided as a reference template only.

### 3. Run the Ingestion Job

```bash
./job/run-ingestion.sh servicenow-ai-poc
```

This will:
- Create the Kubernetes Job
- Follow the logs in real-time
- Show final status

## Configuration

### Dry Run (List Files Without Ingesting)

Edit `job/ingestion-job.yaml` and uncomment the dry-run args:

```yaml
args:
  - "--ingest-url"
  - "$(INGEST_URL)"
  - "--dry-run"  # Uncomment this
```

### Limit Number of Files

Edit `job/ingestion-job.yaml` and uncomment/modify the limit args:

```yaml
args:
  - "--ingest-url"
  - "$(INGEST_URL)"
  - "--limit"    # Uncomment these
  - "10"         # Uncomment and change number
```

### Custom Bucket/Prefix

Edit `job/secret.yaml`:

```yaml
stringData:
  MINIO_BUCKET: "your-bucket-name"
  MINIO_PREFIX: "your/path/prefix/"
```

## Monitoring

### Check Job Status

```bash
oc get job minio-ingestion -n servicenow-ai-poc
```

### View Logs

```bash
oc logs job/minio-ingestion -n servicenow-ai-poc
```

### Check Pod Status

```bash
oc get pods -l app=minio-ingestion -n servicenow-ai-poc
```

## Troubleshooting

### Job Failed

```bash
# Get detailed job info
oc describe job minio-ingestion -n servicenow-ai-poc

# Check pod logs
oc logs -l app=minio-ingestion -n servicenow-ai-poc

# Check pod events
oc describe pod -l app=minio-ingestion -n servicenow-ai-poc
```

### MinIO Connection Issues

- Verify endpoint URL is correct
- Check access key and secret key
- Ensure MinIO is accessible from the cluster
- Verify bucket name and prefix exist

### Doc-Ingest Service Issues

```bash
# Check if service is running
oc get pods -l app=doc-ingest-service -n servicenow-ai-poc

# Test service connectivity from job pod
oc exec -it <job-pod> -n servicenow-ai-poc -- \
  curl http://doc-ingest-service:8001/health
```

## Cleanup

### Delete Job

```bash
oc delete job minio-ingestion -n servicenow-ai-poc
```

### Delete Secret (if needed)

```bash
oc delete secret minio-credentials -n servicenow-ai-poc
```

## Files

- `Containerfile` - Container image definition
- `secret.yaml` - MinIO credentials secret template
- `ingestion-job.yaml` - Kubernetes Job manifest
- `build-and-push.sh` - Build and push container script
- `run-ingestion.sh` - Run the ingestion job script
- `README.md` - This file

## Container Image

- **Registry**: quay.io/wjackson/minio-ingestion-job
- **Base**: Red Hat UBI 9 Python 3.11
- **Dependencies**: boto3, requests, urllib3
- **Script**: ingest-from-minio.py

## Security

- Container runs as non-root user (UID 1001)
- Drops all capabilities
- Uses RuntimeDefault seccomp profile
- Prevents privilege escalation
- Credentials stored in Kubernetes Secret
