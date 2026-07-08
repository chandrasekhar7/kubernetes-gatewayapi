# Master Interview Study Guide: Modernizing 3-Tier Web Apps on Kubernetes
## Includes Local Minikube, AWS EKS, and Azure AKS Architectures

This guide provides a comprehensive overview of the architecture, technical decisions, and challenges solved during the local migration of the **Apex Bank (Fincoro)** and **MediCenter (Hospital)** applications, as well as how this exact setup scales into production-grade environments on **AWS EKS** and **Azure AKS**.

---

## 🏛️ Local Project Architecture (Minikube)

You successfully migrated and ran two enterprise-grade, three-tier applications from a static **Kind/MetalLB** cluster to a dynamic **Minikube** cluster using **ArgoCD (GitOps)**:

1. **Apex Bank (Fincoro App)**: A secure banking application using **NGINX Gateway Fabric** for ingress routing.
2. **MediCenter (Hospital App)**: A hospital management portal using **Envoy Gateway** for ingress routing.

Both applications share a modern, three-tier microservice architecture:

```mermaid
graph TD
    Client[Client Browser / Curl] -->|HTTPS: port 443| LB[LoadBalancer Service]
    LB -->|Gateway API| IngressController[Ingress Controller<br/>NGINX Fabric / Envoy Gateway]
    
    subgraph K8s Namespaces
        IngressController -->|Route: /| Web[Web Portal Frontend<br/>Role: frontend]
        IngressController -->|Route: /auth| Auth[Auth Service<br/>Role: auth]
        IngressController -->|Route: /dashboard| Dash[Dashboard Service<br/>Role: dashboard]
        IngressController -->|Route: /api v1| API_V1[Core API Service v1<br/>Role: api]
        IngressController -->|Route: /api v2| API_V2[Core API Service v2<br/>Role: api-canary]
    end
```

### Key Local Challenges Solved
* **ArgoCD Kustomize Load Restriction**: Resolved ArgoCD `ComparisonError` failures by nesting certificate and gateway manifests directly within the application directories (`fincoro-app/` and `hospital-app/`), avoiding parent directory (`../`) traversals.
- **CRD Bootstrapping Order**: Installed cert-manager, Gateway API, NGINX Gateway Fabric, and Envoy Gateway CRDs before syncing resource manifests.
- **Minikube Dynamic Load Balancer Integration**: Replaced static IPs with native LoadBalancer services (`minikube tunnel`) to assign IP addresses dynamically.
- **Local Image Loading**: Loaded the custom `fincoro-app:latest` image directly into Minikube's image cache (`minikube image load`).

---

## ☁️ Production Architecture: AWS EKS

In a production environment on **AWS EKS**, static configurations are replaced by native cloud integrations.

```mermaid
graph TD
    User[Web Client] -->|Route 53 DNS| NLB[AWS Network Load Balancer]
    NLB -->|AWS Load Balancer Controller| EKS_GW[EKS Gateway API Controller]
    EKS_GW -->|HTTPRoute| Pods[Application Pods]
    
    subgraph AWS Security & Certs
        CertManager[cert-manager] -->|DNS-01 Challenge| Route53[Route 53]
        CertManager -->|IAM Role via IRSA| AWS_IAM[AWS IAM]
    end
```

### 1. Ingress & Load Balancing
* **AWS Load Balancer Controller (ALBC)**: Manages Network Load Balancers (NLB) or Application Load Balancers (ALB) dynamically when `Gateway` resources are declared.
* **Service Type**: The gateway controller provisions an AWS NLB in **IP target mode**, routing traffic directly from the NLB to the pod IPs, bypassing the latency of kube-proxy routing.

### 2. DNS & Domain Mapping
* **ExternalDNS**: Dynamically synchronizes Kubernetes `HTTPRoute` hostnames (e.g. `api.apex.local` -> `api.fincoro.com`) with **AWS Route 53** hosted zones, automating record creation and deletion.

### 3. Certificate Management & Security
* **cert-manager + Let's Encrypt (DNS-01)**: Automates TLS. To prove ownership of the domain without exposing API keys, cert-manager uses **IAM Roles for Service Accounts (IRSA)** to temporarily assume an AWS IAM role and update DNS TXT records in Route 53.
* **Alternative (AWS Certificate Manager)**: Integrate ACM directly with the NLB, offloading TLS termination at the AWS infrastructure layer instead of the cluster.

---

## ☁️ Production Architecture: Azure AKS

In a production environment on **Azure AKS**, the deployment utilizes native Azure Resource Manager integrations.

```mermaid
graph TD
    User[Web Client] -->|Azure DNS| AGW[Azure Application Gateway]
    AGW -->|Application Routing Add-on| AKS_GW[AKS Gateway API Controller]
    AKS_GW -->|HTTPRoute| Pods[Application Pods]
    
    subgraph Azure Identity & Secrets
        WorkloadID[Azure Workload Identity] -->|OIDC Federation| KeyVault[Azure Key Vault]
        CSIDriver[Secrets Store CSI Driver] -->|Sync Secrets| AKSPods[AKS Pods]
    end
```

### 1. Ingress & Load Balancing
* **AKS Application Routing Add-on**: A managed controller (often based on NGINX or Application Gateway Ingress/Gateway API) that dynamically provisions **Azure Application Gateway** or **Azure Load Balancers**.
* **Azure CNI**: Pods receive native IP addresses from the Azure Virtual Network (VNet), allowing the Azure Application Gateway to route traffic directly to pods.

### 2. DNS & Domain Mapping
* **ExternalDNS**: Configured with Azure Managed Identity to automatically synchronize Kubernetes hostnames with **Azure DNS Zones**.

### 3. Secrets & Certificate Management
* **Azure Key Vault (AKV) + Secrets Store CSI Driver**: Certificates are stored securely in AKV. The CSI Driver mounts these certificates as local volumes inside pods or maps them to Kubernetes TLS secrets automatically.
* **Azure Workload Identity**: Eliminates long-lived service principal client secrets. Kubernetes ServiceAccounts federate with Azure Active Directory (AAD) using OIDC token exchange to access Key Vault securely.

---

## 💬 Practice Q&A for Cloud Interviews (EKS & AKS)

### AWS EKS Interview Questions

#### Q: How do you configure EKS pods to access AWS services securely without using hardcoded access keys?
> **Answer**: I implement **IAM Roles for Service Accounts (IRSA)**. 
> 1. Set up an OpenID Connect (OIDC) provider for the EKS cluster.
> 2. Create an AWS IAM role with the required policies (e.g. Route 53 access for cert-manager).
> 3. Establish a trust relationship between the IAM role and the Kubernetes ServiceAccount.
> 4. Annotate the ServiceAccount with the IAM Role ARN. The EKS pod mutating webhook will automatically inject AWS credentials/tokens into the pod.

#### Q: What is the difference between Instance mode and IP mode for AWS Load Balancers, and which one would you choose?
> **Answer**: 
> - **Instance Mode**: Traffic routes from the NLB/ALB to the NodePorts of the cluster nodes, which then use kube-proxy (iptables/IPVS) to route to the pods. This introduces an extra network hop.
> - **IP Mode**: The AWS Load Balancer Controller routes traffic directly to the pod IP addresses. I would choose **IP Mode** for this microservice architecture because it bypasses kube-proxy, reducing latency and avoiding uneven traffic distribution. It requires the AWS VPC CNI to ensure pods have routable VPC IPs.

---

### Azure AKS Interview Questions

#### Q: How does Azure Workload Identity work in AKS, and how does it replace legacy Managed Identities?
> **Answer**: Azure Workload Identity utilizes **OIDC Federation**.
> 1. AKS acts as an OIDC token issuer.
> 2. A Kubernetes ServiceAccount token is projected into the pod.
> 3. The pod exchanges this Kubernetes token with Azure AD (Microsoft Entra ID) for an Azure access token.
> 4. Unlike legacy pod-managed identity which intercepted traffic on the node metadata IP, Workload Identity is standard-based, faster, and operates at the SDK level inside the application container, making it more secure and compatible with non-Linux node pools.

#### Q: How would you secure and automate certificate updates for an AKS application using Azure Key Vault?
> **Answer**: I would use the **Secrets Store CSI Driver** with the Azure Key Vault provider:
> 1. Store the wildcard TLS certificates in Azure Key Vault.
> 2. Configure a `SecretProviderClass` in AKS defining the vault name and certificates to pull.
> 3. Mount the CSI volume in the Gateway/Ingress deployment and enable `secretObjects` syncing to dynamically generate a Kubernetes `v1/Secret` of type `kubernetes.io/tls`.
> 4. Enable **autorotation** on the CSI driver so that when a certificate is renewed in Key Vault, AKS pulls the updated certificate and hot-reloads the gateway proxy without downtime.
