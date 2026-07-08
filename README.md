# Production-Grade Deployment: Three-Tier Banking Application (Fincoro)
### Kubernetes Gateway API (NGINX Gateway Fabric) | MetalLB LoadBalancer | cert-manager TLS Security

This repository contains the complete implementation and documentation for deploying **Fincoro**, a secure three-tier banking application, on a local Kubernetes cluster (`Kind`) with professional-grade traffic routing, load balancing, and end-to-end TLS encryption.

---

## 🏛️ System Architecture

```mermaid
graph TD
    Client[Client / Web Browser] -->|HTTPS: port 443| MetalLB[MetalLB LoadBalancer<br/>IP: 172.18.255.200]
    MetalLB --> NGINX[NGINX Gateway Fabric<br/>Gateway API Controller]
    
    subgraph Cert-Manager Security
        CM[cert-manager]
        ClusterIssuer[ClusterIssuer: selfsigned-root] -->|signs| CA[CA Certificate: fincoro-ca]
        CA -->|issues| AppCert[Wildcard Cert: fincoro-tls]
        AppCert -->|secured-by| NGINX
    end

    subgraph Banking System Namespace
        NGINX -->|fincoro.local| Frontend[Frontend Service<br/>Port: 8080]
        NGINX -->|auth.fincoro.local| Auth[Auth Service<br/>Port: 8080]
        NGINX -->|dashboard.fincoro.local| Dashboard[Dashboard Service<br/>Port: 8080]
        
        NGINX -->|api.fincoro.local<br/>90% default| API_V1[API Service v1<br/>Port: 8080]
        NGINX -->|api.fincoro.local<br/>10% default or X-Fincoro-Canary| API_V2[API Service v2 (Canary)<br/>Port: 8080]
    end
```

---

## 🛠️ Prerequisites

Ensure you have the following CLI utilities installed locally:
- **Docker** (with subnet `172.18.0.0/16` allocated for the `kind` network)
- **Kind** (Kubernetes in Docker)
- **kubectl** (Kubernetes CLI client)
- **Helm** (Kubernetes Package Manager)
- **curl** & **openssl**

---

## 📦 Directory Structure

```text
.
├── README.md                 # Master Documentation (this file)
├── deploy.sh                 # Sequential Deployment Orchestrator
├── test-ingress.sh           # Comprehensive Ingress & Certificate Validator
├── app/
│   ├── server.js             # Multi-role Node.js high-fidelity banking server
│   └── Dockerfile            # Lightweight Node.js Docker configuration
├── cert-manager/
│   ├── 01-selfsigned-issuer.yaml # ClusterIssuer configuration
│   ├── 02-ca-certificate.yaml    # Root CA Certificate
│   ├── 03-ca-issuer.yaml         # Namespace CA Issuer
│   └── 04-app-certificate.yaml   # Wildcard application TLS certificate
├── fincoro-app/
│   ├── 01-namespace.yaml         # Dedicated banking system namespace
│   ├── 02-deployments.yaml       # Deployments (Frontend, Auth, Dashboard, API V1 & V2)
│   └── 03-services.yaml          # Services (ClusterIP configurations)
├── gateway-api/
│   ├── 01-gateway.yaml           # Gateway listener configuration
│   └── 02-routes.yaml            # Hostname & Canary HTTPRoutes
└── metallb/
    └── 01-metallb-config.yaml    # IP Address Pool & L2 Advertisement config
```

---

## 🚀 Step-by-Step Installation & Deployment Guide

Follow these steps to set up the infrastructure controllers and deploy the Fincoro application.

### Step 1: Install cert-manager
If `cert-manager` is not already installed on your cluster, run the following:
```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.1 \
  --set installCRDs=true
```

### Step 2: Install MetalLB
If `MetalLB` is not running on your cluster:
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml
# Wait for the metallb pods to be fully initialized and running
kubectl wait --namespace metallb-system \
                --for=condition=ready pod \
                --selector=app=metallb \
                --timeout=90s
```

### Step 3: Install NGINX Gateway Fabric
Ensure that the Gateway API Custom Resource Definitions (CRDs) are installed before NGINX Gateway Fabric:
```bash
# Apply Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Apply NGINX Gateway Fabric Manifests
kubectl apply -f https://raw.githubusercontent.com/nginxinc/nginx-gateway-fabric/v1.1.0/deploy/manifests/nginx-gateway.yaml
```

### Step 4: Deploy Fincoro Application & Configuration
Run the automated deployment script which provisions the namespace, configures MetalLB pools, builds/loads the custom container image, sets up CA Issuers, and deploys the Fincoro workloads:
```bash
./deploy.sh
```

---

## 📄 Configuration Manifests Explained

### 1. Load Balancing (MetalLB)
[`metallb/01-metallb-config.yaml`](file:///home/chandra/kubernetes-lab/gatewayapi/metallb/01-metallb-config.yaml) assigns a dedicated IP range from the Kind Docker bridge network subnet (`172.18.0.0/16`) to expose the load-balanced services.

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kind-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.18.255.200-172.18.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: kind-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - kind-pool
```

### 2. TLS Certificates & Trust Chain (cert-manager)
We establish a local trust chain inside the namespace using:
- **ClusterIssuer**: Self-signed issuer that creates our root certificate.
- **CA Certificate**: A root certificate stored in `fincoro-ca-secret` that signs all other certificates.
- **Issuer**: A namespace-scoped issuer referencing the root CA.
- **Certificate**: An application certificate containing subject alternative names (SANs) for all Fincoro subdomains.

Reference configurations:
- [`cert-manager/01-selfsigned-issuer.yaml`](file:///home/chandra/kubernetes-lab/gatewayapi/cert-manager/01-selfsigned-issuer.yaml)
- [`cert-manager/02-ca-certificate.yaml`](file:///home/chandra/kubernetes-lab/gatewayapi/cert-manager/02-ca-certificate.yaml)
- [`cert-manager/03-ca-issuer.yaml`](file:///home/chandra/kubernetes-lab/gatewayapi/cert-manager/03-ca-issuer.yaml)
- [`cert-manager/04-app-certificate.yaml`](file:///home/chandra/kubernetes-lab/gatewayapi/cert-manager/04-app-certificate.yaml)

### 3. NGINX Gateway Configuration
[`gateway-api/01-gateway.yaml`](file:///home/chandra/kubernetes-lab/gatewayapi/gateway-api/01-gateway.yaml) defines the ingress entry points:
- **HTTP (Port 80)**: For `fincoro.local` and wildcards `*.fincoro.local`.
- **HTTPS (Port 443)**: For secure transactions, configured in `Terminate` mode referencing the `fincoro-tls` secret issued by cert-manager.

### 4. Advanced Routing (HTTPRoutes)
[`gateway-api/02-routes.yaml`](file:///home/chandra/kubernetes-lab/gatewayapi/gateway-api/02-routes.yaml) implements the routing logic:
- **Enforced SSL**: Directs all port 80 HTTP traffic to HTTPS port 443 using a `301 RequestRedirect`.
- **Traffic Splitting**: Directs `90%` of API traffic to V1 (`api-service`) and `10%` to V2 (`api-service-v2`).
- **Canary Headers**: Routes requests containing the header `X-Fincoro-Canary: true` exclusively (`100%`) to the V2 canary service.
- **Subdomain Mapping**: Maps `auth.fincoro.local` and `dashboard.fincoro.local` to their corresponding microservices.

---

## 🔍 Validation and Verification

### Option A: Automatic Verification Script
Execute the test script to automatically retrieve the Gateway IP, extract the root certificate, perform secure TLS validation, and test routing weights:
```bash
./test-ingress.sh
```

**Expected Console Output:**
```text
=== Starting Ingress and Routing Validation ===
Fetching Gateway IP address... 172.18.255.200
Extracting Root CA certificate from secret 'fincoro-ca-secret'...
Root CA saved to 'ca.crt'

Test 1: HTTP-to-HTTPS redirect on fincoro.local...
✓ Success: HTTP Redirect to https://fincoro.local/ (HTTP 301)

Test 2: Secure Frontend HTTPS Connection (fincoro.local)...
✓ Success: Correctly reached Frontend via SSL!
Response Summary: Title is 'Wealth Management | Fincoro Bank'

Test 3: Auth Subdomain (auth.fincoro.local)...
✓ Success: Reached Authentication Service via SSL!
Response Summary: Title is 'Secure Authentication | Fincoro Bank'

Test 4: Dashboard Subdomain (dashboard.fincoro.local)...
✓ Success: Reached Dashboard Service via SSL!
Response Summary: Title is 'Financial Dashboard | Fincoro Bank'

Test 5: Canary API Routing without Header (Should split ~90% V1, ~10% V2)...
Ran 20 requests:
  - V1 (fincoro-api v1.0.0): 19 times
  - V2 (fincoro-api v2.0.0-canary): 1 times

Test 6: Forced Canary Routing via Header 'X-Fincoro-Canary: true'...
✓ Success: Header-based routing successfully bypassed weights and reached Canary (V2)!
Response: {"service":"fincoro-api","version":"2.0.0-canary","status":"ok","timestamp":"2026-06-06T06:47:01.785Z"}

=== Verification Finished ===
```

### Option B: Local Browser Testing
To access the application in your local web browser, map the domain names to your Gateway's External IP.

1. Retrieve the Gateway's LoadBalancer IP:
   ```bash
   # For Apex Bank
   kubectl get gateway apex-gateway -n banking-system -o jsonpath='{.status.addresses[0].value}'

   # For MediCenter
   kubectl get gateway hospital-gateway -n hospital-system -o jsonpath='{.status.addresses[0].value}'
   ```
2. Append the mapping to your local `/etc/hosts` file (substitute with your actual gateway IPs):
   ```text
   # Apex Banking Application Ingress (substitute <APEX_GATEWAY_IP> with the actual IP)
   <APEX_GATEWAY_IP> apex.local api.apex.local auth.apex.local dashboard.apex.local

   # MediCenter Hospital Application Ingress (substitute <HOSPITAL_GATEWAY_IP> with the actual IP)
   <HOSPITAL_GATEWAY_IP> medicenter.local api.medicenter.local auth.medicenter.local dashboard.medicenter.local
   ```
3. To trust the SSL certificates in your local browser, import the extracted `ca.crt` (or `hospital-ca.crt`) file into your browser's **Authorities certificate store** (Settings -> Privacy & Security -> Security -> Manage Certificates -> Authorities -> Import).
4. Navigate to `https://apex.local` or `https://medicenter.local` in your browser.

---

## ☸️ Minikube LoadBalancer Integration

In Kind, MetalLB was required to handle Service type `LoadBalancer` allocations on the Docker network. In Minikube, we can use the native LoadBalancer tunnel which routes external traffic into the cluster.

To allow Minikube to assign LoadBalancer IPs dynamically, the static IP addresses (`172.18.255.210`) have been removed from the Gateway (`hospital-gateway`) and the EnvoyProxy configurations.

### Activating the Tunnel
Run this command in a separate terminal window and keep it running:
```bash
minikube tunnel
```
Minikube will prompt for administrative privileges to create networking routes. Once running, the LoadBalancer services for both `apex-gateway` and `hospital-gateway` will receive external IPs (typically `127.0.0.1` or the Minikube node IP).

---

## 🐙 ArgoCD Integration

Both three-tier applications have been configured to support GitOps deployments via ArgoCD using **Kustomize**. Kustomization files aggregate all resource components (namespace, deployments, services, cert-manager certificates, and gateways) so that they can be synced as single units.

### Directory Structure with ArgoCD
```text
.
├── argocd/
│   ├── fincoro-app.yaml        # ArgoCD Application manifest for Apex Bank
│   ├── hospital-app.yaml       # ArgoCD Application manifest for MediCenter
│   └── infra-bootstrap.yaml    # ArgoCD Application manifest for the ClusterIssuer
├── fincoro-app/
│   └── kustomization.yaml      # Bundles Fincoro/Apex App and Gateway resources
├── hospital-app/
│   └── kustomization.yaml      # Bundles MediCenter App and Gateway resources
└── cert-manager/
    └── kustomization.yaml      # Bundles shared ClusterIssuer
```

### Steps to Deploy via ArgoCD

1. **Push Changes to your Git Repository**:
   ArgoCD requires access to your repository to pull the Kustomize structures. Initialize git (if not already done), commit the changes, and push to your remote repository (e.g. GitHub):
   ```bash
   git init
   git add .
   git commit -m "feat: add minikube and argocd kustomize support"
   git remote add origin <your-git-repo-url>
   git push -u origin main
   ```

2. **Configure your Repo URL in ArgoCD manifests**:
   Edit the `repoURL` value in the three manifests under the `argocd/` directory:
   - `argocd/infra-bootstrap.yaml`
   - `argocd/fincoro-app.yaml`
   - `argocd/hospital-app.yaml`

   Replace `'https://github.com/YOUR_USERNAME/kubernetes-gatewayapi.git'` with your actual repository URL.

3. **Deploy the Shared Infrastructure**:
   Apply the global `ClusterIssuer` Application:
   ```bash
   kubectl apply -f argocd/infra-bootstrap.yaml
   ```

4. **Deploy the Applications**:
   Apply the ArgoCD Applications for Apex Bank and MediCenter:
   ```bash
   kubectl apply -f argocd/fincoro-app.yaml
   kubectl apply -f argocd/hospital-app.yaml
   ```

5. **Verify Syncing**:
   Open the ArgoCD dashboard or run:
   ```bash
   argocd app list
   ```
   Both applications will be automatically reconciled, namespace and resources created, and Gateway LoadBalancer IPs provisioned by `minikube tunnel`!

