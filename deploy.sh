#!/usr/bin/env bash

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Starting Deployment of Three-Tier Banking Application (Apex Bank) ===${NC}"

# 0. Build and Load Docker Image
echo -e "${YELLOW}Step 0: Building and loading custom banking application image...${NC}"
docker build -t fincoro-app:latest app/
echo "Loading image into 'engineering-lab' Kind cluster..."
kind load docker-image fincoro-app:latest --name engineering-lab

# 1. Create Namespace
echo -e "${YELLOW}Step 1: Creating 'banking-system' Namespace...${NC}"
kubectl apply -f fincoro-app/01-namespace.yaml

# 2. Configure MetalLB
echo -e "${YELLOW}Step 2: Configuring MetalLB IPAddressPool and L2Advertisement...${NC}"
kubectl apply -f metallb/01-metallb-config.yaml

# 3. Configure cert-manager TLS
echo -e "${YELLOW}Step 3: Setting up TLS Certificates using cert-manager...${NC}"
echo "Applying self-signed root ClusterIssuer..."
kubectl apply -f cert-manager/01-selfsigned-issuer.yaml

echo "Applying CA Certificate..."
kubectl apply -f fincoro-app/cert-manager/02-ca-certificate.yaml

echo "Waiting for CA Certificate to be issued..."
kubectl wait --for=condition=Ready certificate/apex-root-ca -n banking-system --timeout=30s

echo "Applying CA Issuer..."
kubectl apply -f fincoro-app/cert-manager/03-ca-issuer.yaml

echo "Applying Application TLS Certificate..."
kubectl apply -f fincoro-app/cert-manager/04-app-certificate.yaml

echo "Waiting for Application TLS Certificate to be issued..."
kubectl wait --for=condition=Ready certificate/apex-app-cert -n banking-system --timeout=30s

# 4. Deploy Application
echo -e "${YELLOW}Step 4: Deploying Apex Application Components...${NC}"
kubectl apply -f fincoro-app/02-deployments.yaml
kubectl apply -f fincoro-app/03-services.yaml

echo "Waiting for application rollouts to complete..."
kubectl rollout status deployment/web-portal -n banking-system --timeout=60s
kubectl rollout status deployment/user-console -n banking-system --timeout=60s
kubectl rollout status deployment/identity-service -n banking-system --timeout=60s
kubectl rollout status deployment/core-api -n banking-system --timeout=60s
kubectl rollout status deployment/core-api-canary -n banking-system --timeout=60s

# 5. Configure Gateway API
echo -e "${YELLOW}Step 5: Configuring NGINX Gateway Fabric and HTTPRoutes...${NC}"
kubectl apply -f fincoro-app/gateway-api/01-gateway.yaml
kubectl apply -f fincoro-app/gateway-api/02-routes.yaml

echo "Waiting for Gateway to be accepted and programmed..."
kubectl wait --for=condition=Accepted gateway/apex-gateway -n banking-system --timeout=60s
kubectl wait --for=condition=Programmed gateway/apex-gateway -n banking-system --timeout=60s

echo -e "${GREEN}=== Apex Banking Application Successfully Deployed! ===${NC}"
echo -e "Gateway Address: $(kubectl get gateway apex-gateway -n banking-system -o jsonpath='{.status.addresses[0].value}')"
