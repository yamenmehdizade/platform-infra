# Architecture Overview

## High-Level Design

This infrastructure follows a **3-tier, multi-AZ, multi-environment** architecture deployed on AWS eu-central-1 (Frankfurt).

Internet

    │

▼

┌─────────────────────────────────────────┐

│  CloudFront + WAF                        │

│  OWASP rules, SQLi, rate limiting        │

└─────────────────────┬───────────────────┘

               │

┌─────────────────▼───────────────────┐

    │  Application Load Balancer           │

│  TLS termination, HTTPS only         │

└─────────────────┬───────────────────┘

│

┌─────────────────────▼───────────────────┐

│  VPC 10.x.0.0/16                         │

│                                          │

│  Public Subnets                          │

│  ┌──────────┐ ┌──────────┐ ┌──────────┐ │

│  │  AZ-a    │ │  AZ-b    │ │  AZ-c    │ │

│  │ NAT GW   │ │ NAT GW   │ │ NAT GW   │ │

│  └──────────┘ └──────────┘ └──────────┘ │

│                                          │

│  Private App Subnets                     │

│  ┌──────────────────────────────────┐    │

│  │  EKS Worker Nodes                │    │

│  │  ┌──────────┐ ┌──────────────┐   │    │

│  │  │ Frontend │ │ Backend API  │   │    │

│  │  │  nginx   │ │  Node.js     │   │    │

│  │  └──────────┘ └──────────────┘   │    │

│  │  ┌──────────┐ ┌──────────────┐   │    │

│  │  │  ArgoCD  │ │  Prometheus  │   │    │

│  │  │  GitOps  │ │  Grafana     │   │    │

│  │  └──────────┘ └──────────────┘   │    │

│  └──────────────────────────────────┘    │

│                                          │

│  Private DB Subnets                      │

│  ┌──────────────────────────────────┐    │

│  │  PostgreSQL 17 (CloudNativePG)   │    │

│  │  EBS gp3 persistent storage      │    │

│  └──────────────────────────────────┘    │

└──────────────────────────────────────────┘

---

## VPC Design

### CIDR Allocation

| Environment | VPC CIDR | Public | Private App | Private DB |
|-------------|----------|--------|-------------|------------|
| dev | 10.0.0.0/16 | 10.0.1-3.0/24 | 10.0.11-13.0/24 | 10.0.21-23.0/24 |
| stage | 10.1.0.0/16 | 10.1.1-3.0/24 | 10.1.11-13.0/24 | 10.1.21-23.0/24 |
| prod | 10.2.0.0/16 | 10.2.1-3.0/24 | 10.2.11-13.0/24 | 10.2.21-23.0/24 |

### Routing Design

Public Subnet Route Table:

0.0.0.0/0 → Internet Gateway

10.x.0.0/16 → localPrivate App Route Table:

0.0.0.0/0 → NAT Gateway (AZ-local)

10.x.0.0/16 → localPrivate DB Route Table:

10.x.0.0/16 → local

  (no default route — no internet access)

**Why AZ-local NAT Gateways?**
Cross-AZ data transfer costs $0.01/GB. In prod, each AZ has its own NAT Gateway to eliminate cross-AZ traffic and provide AZ-level fault isolation.

---

## EKS Architecture

### Control Plane
AWS-managed. Highly available across 3 AZs. API server endpoint accessible via kubectl from authorised IAM identities.

### Node Groups
Managed node groups in private app subnets. Auto Scaling Group with min/desired/max configuration.

| Environment | Instance | Min | Desired | Max |
|-------------|----------|-----|---------|-----|
| dev | t3.medium | 1 | 3 | 4 |
| stage | t3.large | 1 | 2 | 4 |
| prod | m5.xlarge | 2 | 3 | 10 |

### Key Add-ons

| Add-on | Purpose |
|--------|---------|
| aws-vpc-cni | Pod networking — each pod gets a VPC IP |
| aws-ebs-csi-driver | EBS volume provisioning for PVCs |
| coredns | Cluster-internal DNS resolution |
| kube-proxy | Service routing via iptables |

### IRSA (IAM Roles for Service Accounts)

IRSA allows pods to assume IAM roles without node-level credentials. Each workload gets exactly the permissions it needs.

Pod → ServiceAccount (annotated with role ARN)

→ OIDC Token (auto-injected by EKS)

→ AWS STS AssumeRoleWithWebIdentity

→ Temporary credentials (15 min TTL)

→ AWS API call

| Service Account | IAM Role | Permissions |
|----------------|----------|-------------|
| aws-load-balancer-controller | platform-{env}-alb-controller | EC2, ELB APIs |
| cert-manager | platform-{env}-cert-manager | Route53 DNS validation |
| external-dns | platform-{env}-external-dns | Route53 record management |
| ebs-csi-controller-sa | platform-{env}-ebs-csi | EC2 volume management |
| external-secrets | platform-{env}-external-secrets | SecretsManager:GetSecretValue |
| github-actions (OIDC) | platform-{env}-github-actions | ECR push, EKS describe |

---

## GitOps Architecture

### App of Apps Pattern

kubectl apply -f gitops/{env}/apps/root-app.yaml

│

▼

ArgoCD reads gitops/{env}/apps/

│

┌─────────┼─────────┐

▼         ▼         ▼

alb-controller  cert-manager  backend

external-dns    monitoring    frontend

cloudnative-pg  trivy         loki

external-secrets-operator     secrets-config

### Sync Policy

Every ArgoCD Application is configured with:

```yaml
syncPolicy:
  automated:
    prune: true      # Remove resources deleted from Git
    selfHeal: true   # Revert manual cluster changes to Git state
```

`selfHeal: true` is the core of GitOps — the cluster always converges to what is in GitHub.

---

## CI/CD Pipeline

Developer pushes to apps/backend/** or apps/frontend/**

│

▼

build-backend job:

Checkout code
Configure AWS (OIDC — no stored credentials)
Docker build (multi-stage)
Trivy scan — CRITICAL CVEs block the pipeline
Push to ECR (tagged with git SHA)

│

▼ (parallel)

build-frontend job:

Same flow for frontend image

│

▼ (after both pass)

deploy job:
Determine target cluster from branch

master → platform-stage

release/* → platform-prod
helm upgrade --install
Smoke test via kubectl exec

### Branch → Environment Mapping

| Branch | Target Cluster | Trigger |
|--------|---------------|---------|
| feature/* | none | PR checks only |
| master | platform-stage | Auto on merge |
| release/* | platform-prod | Auto on push |

---

## Secrets Architecture

AWS Secrets Manager

platform/{env}/db-credentials

├── username

├── password

├── host

├── port

└── dbname

│

│ (sync every 1 hour)

▼

External Secrets Operator

ClusterSecretStore → AWS provider (IRSA)

│

▼

Kubernetes Secret: db-credentials (namespace: backend)

DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD

│

│ (secretKeyRef)

▼

Backend Pod environment variables
**Zero secrets in Git. Zero secrets in Docker images. Zero long-lived credentials.**

---

## Observability Stack

┌─────────────────────────────────────────┐

│  Data Sources                            │

│  Node Exporter → CPU, RAM, Disk, Network │

│  kube-state-metrics → Pod, Deployment    │

│  App /metrics → Custom business metrics  │

│  Promtail → Pod stdout/stderr logs       │

└──────────────┬──────────────────────────┘

│

┌──────────▼──────────┐

│  Prometheus          │  7-day retention

│  AlertManager        │  → Slack/PagerDuty

└──────────┬──────────┘

│

┌──────────▼──────────┐

│  Grafana             │

│  Kubernetes Cluster  │  gnetId: 7249

│  Node Exporter       │  gnetId: 1860

│  Custom App metrics  │

└─────────────────────┘

│

┌──────────▼──────────┐

│  Loki                │  Log aggregation

└─────────────────────┘

---

## Security Layers

Layer 1 — Edge

WAF WebACL:

AWSManagedRulesCommonRuleSet (OWASP Top 10)
AWSManagedRulesSQLiRuleSet
AWSManagedRulesKnownBadInputsRuleSet
Rate limiting: 2000 req/5min per IP

Layer 2 — Network

VPC 3-tier segmentation
Security Groups (stateful, least-privilege)
NACLs (stateless, subnet-level)
No direct internet access to app/db tiers

Layer 3 — Workload

IRSA (pod-level IAM, not node-level)
Pod Security Standards (restricted namespace)
Non-root containers
Read-only root filesystem

Layer 4 — Data

Secrets Manager (no secrets in Git)
EBS encryption at rest
TLS in transit

Layer 5 — Detection

GuardDuty (CloudTrail + K8s audit + VPC flows)
Security Hub (CIS AWS Foundations Benchmark)
Trivy Operator (continuous CVE scanning)
VPC Flow Logs

---

## Terraform Module Structure

modules/

├── vpc/          VPC, subnets, IGW, NAT GW, route tables, NACLs

├── eks/          EKS cluster, node groups, OIDC, addons, aws-auth

├── irsa/         All IAM roles for service accounts

├── argocd/       ArgoCD Helm release, namespace

├── secrets/      Secrets Manager secrets per environment

└── security/     WAF WebACL, GuardDuty detector, Security Hub

Each module:
- Has its own `variables.tf`, `outputs.tf`, `main.tf`
- Is called from `environments/{env}/infra/main.tf`
- Shares no state with other modules — communication via outputs only
- Is reused across dev, stage, and prod with different variable values
