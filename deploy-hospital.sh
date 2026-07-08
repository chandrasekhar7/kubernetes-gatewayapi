#!/usr/bin/env bash

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Starting Deployment of Hospital Application (MediCenter) ===${NC}"

# 0. Build and Load Docker Image
echo -e "${YELLOW}Step 0: Rebuilding and loading custom banking & hospital application image...${NC}"
docker build -t fincoro-app:latest app/
echo "Loading image into 'engineering-lab' Kind cluster..."
kind load docker-image fincoro-app:latest --name engineering-lab

# 1. Create Namespace
echo -e "${YELLOW}Step 1: Creating 'hospital-system' Namespace...${NC}"
kubectl apply -f hospital-app/01-namespace.yaml

# 2. Configure cert-manager TLS
echo -e "${YELLOW}Step 2: Setting up TLS Certificates using cert-manager...${NC}"
echo "Applying self-signed root ClusterIssuer..."
kubectl apply -f cert-manager/01-selfsigned-issuer.yaml

echo "Applying Hospital CA Certificate..."
kubectl apply -f hospital-app/hospital-cert/01-ca-certificate.yaml

echo "Waiting for CA Certificate to be issued..."
kubectl wait --for=condition=Ready certificate/medicenter-root-ca -n hospital-system --timeout=30s

echo "Applying Hospital CA Issuer..."
kubectl apply -f hospital-app/hospital-cert/02-ca-issuer.yaml

echo "Applying Application TLS Certificate..."
kubectl apply -f hospital-app/hospital-cert/03-app-certificate.yaml

echo "Waiting for Application TLS Certificate to be issued..."
kubectl wait --for=condition=Ready certificate/medicenter-app-cert -n hospital-system --timeout=30s

# 3. Deploy Application
echo -e "${YELLOW}Step 3: Deploying MediCenter Application Components...${NC}"
kubectl apply -f hospital-app/02-deployments.yaml
kubectl apply -f hospital-app/03-services.yaml

echo "Waiting for application rollouts to complete..."
kubectl rollout status deployment/med-portal -n hospital-system --timeout=60s
kubectl rollout status deployment/med-dashboard -n hospital-system --timeout=60s
kubectl rollout status deployment/med-auth -n hospital-system --timeout=60s
kubectl rollout status deployment/med-api -n hospital-system --timeout=60s
kubectl rollout status deployment/med-api-canary -n hospital-system --timeout=60s

# 4. Configure Gateway API (Envoy Gateway)
echo -e "${YELLOW}Step 4: Configuring Envoy GatewayClass, Gateway, and HTTPRoutes...${NC}"
kubectl apply -f hospital-app/hospital-gateway/04-envoy-proxy.yaml
kubectl apply -f hospital-app/hospital-gateway/01-gateway-class.yaml
kubectl apply -f hospital-app/hospital-gateway/02-gateway.yaml
kubectl apply -f hospital-app/hospital-gateway/03-routes.yaml

echo "Waiting for Envoy Gateway to be accepted and programmed..."
kubectl wait --for=condition=Accepted gateway/hospital-gateway -n hospital-system --timeout=90s
kubectl wait --for=condition=Programmed gateway/hospital-gateway -n hospital-system --timeout=90s

echo -e "${GREEN}=== MediCenter Hospital Application Successfully Deployed! ===${NC}"
echo -e "Gateway Address: $(kubectl get gateway hospital-gateway -n hospital-system -o jsonpath='{.status.addresses[0].value}')"
chmod +x deploy-hospital.sh || true
