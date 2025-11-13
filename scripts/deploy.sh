#!/bin/bash

# Document Ingestion Service Deployment Script
# Deploys the doc-ingest service to OpenShift using pre-built Quay image

set -e

NAMESPACE=${1:-servicenow-ai-poc}

echo "🚀 Deploying Document Ingestion Service to namespace: $NAMESPACE"
echo "================================================================="

# Check if namespace exists
if ! oc get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ ERROR: Namespace '$NAMESPACE' does not exist!"
    echo ""
    echo "Please deploy the pgvector backend first:"
    echo "  cd ../pgvector-poc-backend"
    echo "  ./scripts/deploy-backend.sh $NAMESPACE"
    exit 1
fi

# Check if postgres is running
if ! oc get statefulset postgres-pgvector -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ ERROR: PostgreSQL backend not found in namespace '$NAMESPACE'"
    echo ""
    echo "Please deploy the pgvector backend first:"
    echo "  cd ../pgvector-poc-backend"
    echo "  ./scripts/deploy-backend.sh $NAMESPACE"
    exit 1
fi

echo "✅ Prerequisites verified"
echo ""

echo "📦 Step 1: Deploying Document Ingestion Service..."
echo "   Using pre-built image: quay.io/wjackson/doc-ingest-service:latest"
oc apply -f manifests/configmap.yaml -n "$NAMESPACE"
oc apply -f manifests/deployment.yaml -n "$NAMESPACE"
oc apply -f manifests/service.yaml -n "$NAMESPACE"
oc apply -f manifests/route.yaml -n "$NAMESPACE"
oc apply -f manifests/networkpolicy.yaml -n "$NAMESPACE"

echo ""
echo "⏳ Step 2: Waiting for deployment to be ready..."
oc rollout status deployment/doc-ingest-service -n "$NAMESPACE" --timeout=5m

echo ""
echo "🔍 Step 3: Verifying service health..."
ROUTE=$(oc get route doc-ingest-service -n "$NAMESPACE" -o jsonpath='{.spec.host}')
echo "Route URL: https://$ROUTE"

# Wait a moment for route to propagate
sleep 5

# Test health endpoint
if curl -sf "https://$ROUTE/health" > /dev/null; then
    echo "✅ Health check passed!"
else
    echo "⚠️  Health check failed - service may still be initializing"
    echo "Check logs: oc logs -f deployment/doc-ingest-service -n $NAMESPACE"
fi

echo ""
echo "================================================================="
echo "✅ Document Ingestion Service deployed successfully!"
echo ""
echo "Service URL: https://$ROUTE"
echo "Health endpoint: https://$ROUTE/health"
echo ""
echo "Test ingestion:"
echo "  curl -X POST https://$ROUTE/ingest -F 'file=@test.md'"
echo ""
echo "Monitor deployment:"
echo "  oc get pods -n $NAMESPACE -l app=doc-ingest-service -w"
echo ""
echo "Check logs:"
echo "  oc logs -f deployment/doc-ingest-service -n $NAMESPACE"
