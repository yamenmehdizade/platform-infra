# Platform Infrastructure

![Terraform](https://img.shields.io/badge/Terraform-1.7+-purple)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.33-blue)
![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-orange)
![AWS](https://img.shields.io/badge/AWS-eu--central--1-yellow)

Production-grade AWS infrastructure built with Terraform and GitOps principles.
Designed to demonstrate Cloud/DevOps engineering skills for Swiss and Austrian markets.

---

## Architectur


## Stack

| Layer | Technology |
|-------|-----------|
| Cloud | AWS (eu-central-1) |
| IaC | Terraform >= 1.7, modular, multi-environment |
| Container Platform | EKS 1.33, Kubernetes |
| GitOps | ArgoCD (App of Apps pattern) |
| CI/CD | GitHub Actions (planned) |
| Observability | Prometheus, Grafana, Loki, AlertManager |
| Security | WAF, GuardDuty, Security Hub, Trivy Operator |
| Database | PostgreSQL 17 (CloudNativePG) |
| DNS/TLS | ExternalDNS, cert-manager |

## Repository Structure

## Infrastructure Components

### Networking
- VPC: 10.0.0.0/16 across 3 Availability Zones
- Public subnets: ALB, NAT Gateway
- Private App subnets: EKS worker nodes
- Private DB subnets: PostgreSQL, ElastiCache
- NAT Gateway for outbound internet access
- VPC Flow Logs enabled

### EKS Cluster
- Kubernetes 1.33 (latest)
- Managed node groups: t3.medium
- OIDC provider for IRSA
- EBS CSI Driver, VPC CNI with prefix delegation
- Add-ons: CoreDNS, kube-proxy, aws-node

### GitOps (ArgoCD)
App of Apps pattern — single root-app manages all applications:
- AWS Load Balancer Controller
- cert-manager
- ExternalDNS
- Backend API
- Frontend
- PostgreSQL (CloudNativePG)
- Prometheus + Grafana + Loki
- Trivy Operator

### Security
- **WAF**: OWASP Top 10, SQL injection, Known Bad Inputs, rate limiting (2000 req/5min)
- **GuardDuty**: Threat detection — S3, Kubernetes audit logs, malware protection
- **Security Hub**: CIS AWS Foundations Benchmark, AWS Foundational Security
- **IRSA**: Pod-level IAM — least privilege per service account
- **Trivy Operator**: Continuous vulnerability scanning for all container images

### Observability
- **Prometheus**: Cluster and application metrics
- **Grafana**: Kubernetes Cluster and Node Exporter dashboards
- **Loki**: Centralized log aggregation
- **AlertManager**: Alert routing and notification

## Quick Start

### Prerequisites
- AWS CLI configured
- Terraform >= 1.7
- kubectl
- Helm >= 3.0

### Deploy

```bash
# 1. Bootstrap state backend
cd terraform/bootstrap
terraform init && terraform apply

# 2. Deploy infrastructure (Phase 1 - AWS resources)
cd ../environments/dev
terraform init -backend-config=../../backend/dev.hcl
terraform apply

# 3. Update kubeconfig
aws eks update-kubeconfig --name platform-dev --region eu-central-1

# 4. Deploy ArgoCD + platform addons (Phase 2)
# Uncomment helm/kubernetes providers in terraform.tf
terraform apply

# 5. Deploy applications via GitOps
kubectl apply -f gitops/apps/root-app.yaml
```

### Verify

```bash
# Check all ArgoCD applications
kubectl get applications -n argocd

# Check all pods
kubectl get pods -A

# Test backend API
kubectl port-forward svc/backend 8080:8080 -n backend
curl http://localhost:8080/health
```

## Sprints

| Sprint | Description | Status |
|--------|-------------|--------|
| Sprint 1 | VPC, Subnets, NAT, Route Tables | ✅ Done |
| Sprint 2 | EKS Cluster, Node Groups, OIDC | ✅ Done |
| Sprint 3 | IRSA — ALB, cert-manager, ExternalDNS | ✅ Done |
| Sprint 4 | ArgoCD, GitOps, App of Apps | ✅ Done |
| Sprint 5 | Frontend, Backend API, PostgreSQL | ✅ Done |
| Sprint 6 | Prometheus, Grafana, Loki | ✅ Done |
| Sprint 7 | WAF, GuardDuty, Security Hub, Trivy | ✅ Done |

## Author

Network Security Engineer → Cloud/DevOps Engineer transition project.
Target: Cloud/DevOps positions in Switzerland and Austria.

- 10+ years networking and network security experience
- AWS, Terraform, Kubernetes, GitOps, DevSecOps



