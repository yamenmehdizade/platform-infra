# Platform Infrastructure

[![CI](https://github.com/yamenmehdizade/platform-infra/actions/workflows/pr-checks.yml/badge.svg)](https://github.com/yamenmehdizade/platform-infra/actions)
[![Build](https://github.com/yamenmehdizade/platform-infra/actions/workflows/build-push.yml/badge.svg)](https://github.com/yamenmehdizade/platform-infra/actions)
![Terraform](https://img.shields.io/badge/Terraform-1.7+-purple)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.33-blue)
![ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD-orange)
![AWS](https://img.shields.io/badge/AWS-eu--central--1-yellow)
![License](https://img.shields.io/badge/License-MIT-green)

> Production-grade AWS infrastructure built with Terraform, Kubernetes, and GitOps principles.
> Designed by a Network Security Engineer transitioning to Cloud/DevOps — targeting Swiss and Austrian markets.

---

## Overview

This project demonstrates a complete, real-world cloud infrastructure deployment across **3 isolated environments** (dev, stage, prod). It is not a tutorial project — every component reflects patterns used in production environments at Swiss and Austrian enterprises.

**What makes this different:**
- 10+ years of network security experience applied to cloud architecture
- Every design decision is documented with rationale
- Real errors encountered, real fixes applied — all documented
- Security is a first-class concern, not an afterthought

---

## Architecture

Internet → WAF (OWASP rules + rate limiting)

→ ALB (TLS termination)

→ EKS Kubernetes 1.33

├── Frontend (nginx)

├── Backend API (Node.js)

├── PostgreSQL 17 (CloudNativePG)

├── Prometheus + Grafana + Loki

└── ArgoCD (GitOps controller)

### Multi-Environment Design

| Environment | VPC CIDR | Node Type | Node Count | NAT GWs |
|-------------|----------|-----------|------------|---------|
| dev | 10.0.0.0/16 | t3.medium | 2-3 | 1 |
| stage | 10.1.0.0/16 | t3.large | 2 | 2 |
| prod | 10.2.0.0/16 | m5.xlarge | 3 | 3 |

Each environment has its own:
- Isolated VPC with 3-tier subnet design
- EKS cluster with dedicated node groups
- Terraform state file (S3 + DynamoDB lock)
- Secrets Manager secrets
- ArgoCD instance
- WAF WebACL and GuardDuty detector

---

## Stack

| Layer | Technology | Details |
|-------|-----------|---------|
| Cloud | AWS eu-central-1 | Frankfurt region |
| IaC | Terraform >= 1.7 | Modular, multi-environment, remote state |
| Container Platform | EKS 1.33 | Managed node groups, IRSA, EBS CSI |
| GitOps | ArgoCD | App of Apps pattern, selfHeal, automated sync |
| CI/CD | GitHub Actions | OIDC auth, Trivy gate, Helm deploy |
| Observability | Prometheus + Grafana + Loki | Pre-provisioned dashboards |
| Security | WAF + GuardDuty + Security Hub + Trivy | CIS Benchmark, OWASP rules |
| Database | PostgreSQL 17 | CloudNativePG operator, EBS persistence |
| Secrets | AWS Secrets Manager + ESO | Automatic sync, no secrets in Git |
| DNS/TLS | ExternalDNS + cert-manager | Route53 integration |

---

## Repository Structure

platform-infra/

├── terraform/

│   ├── modules/               # Reusable modules

│   │   ├── vpc/               # VPC, subnets, IGW, NAT, routes

│   │   ├── eks/               # EKS cluster, node groups, OIDC

│   │   ├── irsa/              # IAM roles for service accounts

│   │   ├── argocd/            # ArgoCD Helm deployment

│   │   ├── secrets/           # Secrets Manager resources

│   │   └── security/          # WAF, GuardDuty, Security Hub

│   └── environments/

│       ├── dev/

│       │   ├── infra/         # AWS resources (VPC, EKS, IAM)

│       │   └── platform/      # Helm/K8s resources (ArgoCD)

│       ├── stage/

│       └── prod/

├── gitops/

│   ├── apps/                  # Dev ArgoCD Application manifests

│   ├── stage/apps/            # Stage ArgoCD Application manifests

│   ├── prod/apps/             # Prod ArgoCD Application manifests

│   └── helm-values/           # Helm chart overrides per app

├── helm/

│   ├── backend/               # Backend API Helm chart

│   └── frontend/              # Frontend Helm chart

├── apps/

│   ├── backend/               # Node.js API source + Dockerfile

│   ├── frontend/              # nginx dashboard + Dockerfile

│   ├── postgres/              # CloudNativePG cluster manifests

│   ├── secrets/               # Dev ExternalSecret manifests

│   ├── secrets-stage/         # Stage ExternalSecret manifests

│   └── secrets-prod/          # Prod ExternalSecret manifests

├── backend/                   # Terraform backend configs

│   ├── dev-infra.hcl

│   ├── dev-platform.hcl

│   ├── stage-infra.hcl

│   └── prod-infra.hcl

├── docs/                      # Architecture, ADRs, runbooks

├── .github/workflows/         # CI/CD pipelines

└── README.md

---

## Key Design Decisions

### Why EKS over ECS Fargate?
Kubernetes is requested in 75%+ of Cloud/DevOps job descriptions in Switzerland and Austria. EKS enables CKA certification, CNCF ecosystem tools, and skills that transfer to AKS/GKE. See [docs/adr/001-eks-over-ecs.md](docs/adr/001-eks-over-ecs.md).

### Why ArgoCD App of Apps?
A single `kubectl apply` deploys the entire platform. Adding a new application requires one YAML file in `gitops/apps/`. `selfHeal: true` ensures the cluster always converges to the Git state. See [docs/adr/002-app-of-apps-pattern.md](docs/adr/002-app-of-apps-pattern.md).

### Why separate Terraform state per environment?
Independent state files mean a failed prod apply cannot corrupt dev state. Each environment can be destroyed without affecting others. Remote state with S3 + DynamoDB locking prevents concurrent modifications.

### Why External Secrets Operator over Kubernetes Secrets?
Secrets in etcd are base64 encoded, not encrypted. ESO pulls secrets from AWS Secrets Manager at runtime — no secrets ever touch Git, no secrets are stored in container environment variables in plain text.

---

## Security Architecture

This project applies **defence in depth** — 5 security layers:

Layer 1 — Edge:        CloudFront + WAF (OWASP, SQLi, rate limiting)

Layer 2 — Network:     VPC segmentation, NACLs, Security Groups

Layer 3 — Workload:    IRSA least-privilege, Pod Security Standards

Layer 4 — Data:        KMS encryption, Secrets Manager rotation

Layer 5 — Detection:   GuardDuty, Security Hub CIS Benchmark, Trivy

My network security background directly informed this design — Security Groups map to stateful firewall rules, NACLs to stateless ACLs, VPC routing to enterprise routing tables.

---

## Sprint History

| Sprint | Description | Status |
|--------|-------------|--------|
| Sprint 1 | VPC, Subnets, NAT Gateway, Route Tables | ✅ |
| Sprint 2 | EKS 1.33, Node Groups, OIDC Provider | ✅ |
| Sprint 3 | IRSA — ALB Controller, cert-manager, ExternalDNS, EBS CSI | ✅ |
| Sprint 4 | ArgoCD, GitOps App of Apps pattern | ✅ |
| Sprint 5 | Node.js Backend, nginx Frontend, PostgreSQL 17 | ✅ |
| Sprint 6 | Prometheus, Grafana, Loki, AlertManager | ✅ |
| Sprint 7 | WAF, GuardDuty, Security Hub, Trivy Operator | ✅ |
| Sprint 8 | GitHub Actions CI/CD — OIDC, Trivy gate, Helm deploy | ✅ |
| Sprint 9 | Secrets Manager + External Secrets Operator | ✅ |
| Sprint 10 | Stage Environment — isolated cluster, VPC, state | ✅ |
| Sprint 11 | Production Environment — m5.xlarge, 3-AZ NAT | ✅ |

---

## Deployment Guide

### Prerequisites

```bash
aws --version          # AWS CLI v2
terraform --version    # >= 1.7.0
kubectl version        # >= 1.28
helm version           # >= 3.0
```

### Phase 1 — Infrastructure (VPC, EKS, IAM)

```bash
cd environments/dev/infra
terraform init -backend-config=../../../backend/dev-infra.hcl
terraform apply -auto-approve
```

### Phase 2 — Platform (ArgoCD)

```bash
aws eks update-kubeconfig --name platform-dev --region eu-central-1

cd environments/dev/platform
terraform init -backend-config=../../../backend/dev-platform.hcl
terraform apply -auto-approve
```

### Phase 3 — Applications (GitOps)

```bash
kubectl apply -f gitops/apps/root-app.yaml
kubectl get applications -n argocd -w
```

### Verify

```bash
# All applications healthy
kubectl get applications -n argocd

# All pods running
kubectl get pods -A | grep -v kube-system

# API health check
kubectl exec -n backend \
  $(kubectl get pods -n backend -o name | head -1) \
  -- wget -qO- http://localhost:8080/health
```

---

## Real Errors Encountered

These are production-class problems solved during development:

| Problem | Root Cause | Fix |
|---------|-----------|-----|
| `data.aws_eks_cluster` error on first apply | Helm provider reads EKS before it exists | Two-phase apply: infra first, platform second |
| PostgreSQL PVCs stuck in Pending | EBS CSI driver had no IRSA role | Added `ebs_csi` IAM role to irsa module |
| Nodes hitting 17-pod limit | t3.medium ENI limit with VPC CNI | Added 3rd node; prefix delegation configured |
| kube-prometheus-stack CRD too large | 262KB annotation limit in ArgoCD | Deployed via Helm directly; Grafana via ArgoCD |
| ArgoCD namespace stuck on destroy | Kubernetes finalizers blocking deletion | Manual finalizer removal via kubectl |
| GitHub OIDC auth failing | `aws-auth` ConfigMap missing github-actions role | Added `kubernetes_config_map_v1_data` resource with `depends_on` |
| Stage secrets pointing to dev path | ESO ExternalSecret had hardcoded dev path | Created environment-specific secret manifests |

---

## Cost Analysis

| Environment | Monthly Estimate | Key Cost Drivers |
|-------------|-----------------|-----------------|
| Dev (active) | ~$150 | EKS $73 + 3x t3.medium + NAT GW |
| Stage (active) | ~$250 | EKS $73 + 2x t3.large + 2x NAT GW |
| Prod (active) | ~$800 | EKS $73 + 3x m5.xlarge + 3x NAT GW |
| Portfolio (intermittent) | ~$20-40/month | Apply → test → destroy workflow |

**Cost optimisation applied:**
- Destroy after each session — EBS volumes checked manually
- Single NAT GW in dev (HA not required for testing)
- VPC Endpoints for S3/ECR to reduce NAT data transfer

---

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Architecture Decision Records](docs/decisions.md)
- [Cost Analysis](docs/cost-analysis.md)
- [Threat Model](docs/threat-model.md)
- [Troubleshooting Guide](docs/troubleshooting.md)
- [Lessons Learned](docs/lessons-learned.md)

---

## About

**Background:** 10+ years in network security — BGP routing, Palo Alto NGFWs, GWLB traffic inspection, hybrid AWS/on-prem connectivity.

**Goal:** Cloud/DevOps Engineer roles in Switzerland and Austria.

**Key insight:** Security Groups are stateful firewall rules. NACLs are stateless ACLs. VPC routing is BGP without the BGP. The concepts were familiar — the tooling was new.

---

*Built with the help of real production errors, documented lessons, and a lot of `terraform destroy`.*
