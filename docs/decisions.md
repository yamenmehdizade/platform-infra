# Architecture Decision Records (ADR)

This document captures the key architectural decisions made during this project,
using the ADR format: Context, Decision, Consequences.

---

## ADR-001: Use EKS over ECS Fargate

**Status:** Accepted

**Context:**
The project needs a container orchestration platform. The two primary AWS options are ECS Fargate (AWS-native, serverless) and EKS (managed Kubernetes). The choice affects skill development, portability, and job market alignment.

**Decision:**
Use EKS (Elastic Kubernetes Service).

**Rationale:**
- Kubernetes appears in 75%+ of Cloud/DevOps job descriptions in Switzerland and Austria
- EKS skills transfer directly to AKS (Azure) and GKE (Google Cloud)
- Enables CKA (Certified Kubernetes Administrator) certification
- Access to the full CNCF ecosystem (ArgoCD, Prometheus, cert-manager, etc.)
- Kubernetes is the industry standard for portable, cloud-agnostic workloads

**Consequences:**
- (+) Marketable, transferable skills
- (+) Rich ecosystem of tools
- (-) Higher operational complexity than Fargate
- (-) Control plane cost ($0.10/hour = ~$73/month per cluster)
- (-) Steeper learning curve

---

## ADR-002: ArgoCD App of Apps Pattern

**Status:** Accepted

**Context:**
The platform has many applications (ALB controller, cert-manager, monitoring, backend, frontend, etc.). These need to be deployed and managed declaratively. Managing each application's ArgoCD definition manually does not scale.

**Decision:**
Use the App of Apps pattern — a single root ArgoCD Application that points to a directory of child Application manifests.

**Rationale:**
- One `kubectl apply -f root-app.yaml` deploys the entire platform
- Adding a new application requires only adding a YAML file to the apps directory
- The root app self-manages — changes to child apps are picked up automatically
- Clear separation between platform addons and business applications

**Consequences:**
- (+) Single entry point for the entire platform
- (+) Easy to add/remove applications via Git
- (+) Scales cleanly across dev, stage, prod
- (-) An error in the root app can affect all children
- (-) Requires understanding ArgoCD's sync waves for ordering

---

## ADR-003: Separate Terraform State per Environment

**Status:** Accepted

**Context:**
The infrastructure spans three environments (dev, stage, prod). State management strategy affects safety, blast radius, and operational flexibility.

**Decision:**
Each environment has its own Terraform state file, stored in S3 with DynamoDB locking. Furthermore, each environment splits into `infra` and `platform` states.
s3://yamen-platform-tfstate-028185488284/

├── dev/infra/terraform.tfstate

├── dev/platform/terraform.tfstate

├── stage/infra/terraform.tfstate

├── stage/platform/terraform.tfstate

├── prod/infra/terraform.tfstate

└── prod/platform/terraform.tfstate

**Rationale:**
- A failed prod apply cannot corrupt dev state
- Each environment can be destroyed independently
- Smaller state files mean faster plan/apply
- DynamoDB locking prevents concurrent modification conflicts

**Consequences:**
- (+) Strong isolation between environments
- (+) Reduced blast radius
- (-) More backend config files to manage
- (-) Cross-environment references require remote state data sources

---

## ADR-004: Split Infra and Platform Terraform Modules

**Status:** Accepted

**Context:**
The Helm and Kubernetes Terraform providers need to read the EKS cluster endpoint. On the first apply, EKS does not exist, causing the providers to fail.

**Decision:**
Split each environment into two root modules:
- `infra/` — AWS resources (VPC, EKS, IAM). AWS provider only.
- `platform/` — Helm/Kubernetes resources (ArgoCD). Reads EKS from remote state.

**Rationale:**
- Eliminates the chicken-and-egg problem of providers depending on resources they create
- The `platform` module reads `infra` outputs via `terraform_remote_state`
- Allows applying infrastructure changes without touching Helm releases

**Consequences:**
- (+) Clean first-apply with no provider errors
- (+) Separate blast radius for AWS vs Kubernetes resources
- (-) Two apply steps instead of one
- (-) Remote state dependency between modules

---

## ADR-005: External Secrets Operator over Native Kubernetes Secrets

**Status:** Accepted

**Context:**
Database credentials and other secrets need to be available to pods. Native Kubernetes Secrets store data base64-encoded in etcd — not encrypted, and visible to anyone with cluster access. Hardcoding secrets in Helm values exposes them in Git.

**Decision:**
Store secrets in AWS Secrets Manager. Use External Secrets Operator (ESO) to sync them into Kubernetes Secrets at runtime.

**Rationale:**
- Secrets never appear in Git
- Secrets are encrypted at rest in Secrets Manager (KMS)
- ESO authenticates to Secrets Manager via IRSA (no static credentials)
- Secrets can be rotated in Secrets Manager without redeploying applications
- Audit trail of secret access via CloudTrail

**Consequences:**
- (+) No secrets in Git or container images
- (+) Centralised secret management and rotation
- (+) Audit logging via CloudTrail
- (-) Additional operator to maintain
- (-) 1-hour sync delay (configurable) between Secrets Manager and Kubernetes

---

## ADR-006: GitHub Actions OIDC over Stored AWS Credentials

**Status:** Accepted

**Context:**
The CI/CD pipeline needs to authenticate to AWS to push images to ECR and deploy to EKS. The traditional approach uses long-lived IAM access keys stored as GitHub secrets.

**Decision:**
Use GitHub Actions OIDC federation. GitHub issues a short-lived OIDC token that AWS STS exchanges for temporary credentials.

**Rationale:**
- No long-lived AWS credentials stored anywhere
- Tokens are scoped to specific repositories and branches
- Credentials are temporary (expire after the job)
- Eliminates the risk of leaked access keys
- AWS-recommended best practice for CI/CD

**Consequences:**
- (+) Zero stored AWS credentials
- (+) Repository-scoped, time-limited access
- (-) Requires OIDC provider setup in IAM
- (-) Trust policy must be carefully scoped (sub claim)

---

## ADR-007: CloudNativePG over Amazon RDS

**Status:** Accepted

**Context:**
The application needs a PostgreSQL database. Options include Amazon RDS (managed, AWS-native) and running PostgreSQL inside Kubernetes via an operator like CloudNativePG.

**Decision:**
Use CloudNativePG operator inside the EKS cluster.

**Rationale:**
- Demonstrates Kubernetes operator and StatefulSet knowledge
- Keeps the database within the GitOps workflow
- No additional managed-service cost during portfolio testing
- Showcases EBS CSI persistent volume integration

**Consequences:**
- (+) Full GitOps management of the database
- (+) Demonstrates advanced Kubernetes skills
- (+) Lower cost for portfolio/testing
- (-) Self-managed — backups, HA, and patching are my responsibility
- (-) Not how most production databases are run (RDS is more common)

**Note:** In a real production environment, Amazon RDS or Aurora would likely be preferred for the reduced operational burden. CloudNativePG was chosen here to demonstrate Kubernetes depth.

---

## ADR-008: Variant B GitOps — Terraform Creates IAM, ArgoCD Deploys Addons

**Status:** Accepted

**Context:**
Platform addons (ALB controller, cert-manager, ExternalDNS) need both IAM roles (AWS) and Helm deployments (Kubernetes). There are two approaches: Terraform manages everything, or Terraform manages only IAM while ArgoCD manages Helm.

**Decision:**
Terraform creates only the IAM/IRSA roles. ArgoCD deploys all addons via the App of Apps pattern.

**Rationale:**
- Keeps all Kubernetes workload management in GitOps
- Terraform handles only what it is best at — AWS resource provisioning
- Clear boundary: Terraform = AWS, ArgoCD = Kubernetes
- Addon upgrades happen via Git commits, not Terraform applies

**Consequences:**
- (+) Clean separation of concerns
- (+) Addon changes are GitOps-managed and auditable
- (-) IAM role ARNs must be passed from Terraform to ArgoCD Helm values
- (-) Two systems to understand for a single addon

---

## ADR-009: Multi-AZ NAT Gateways in Production

**Status:** Accepted

**Context:**
NAT Gateways provide outbound internet access for private subnets. A single NAT Gateway is cheaper but creates a single point of failure and cross-AZ data transfer costs.

**Decision:**
- dev: 1 NAT Gateway (cost optimisation, HA not required)
- stage: 2 NAT Gateways
- prod: 3 NAT Gateways (one per AZ)

**Rationale:**
- In prod, each AZ has its own NAT Gateway for fault isolation
- Eliminates cross-AZ data transfer charges ($0.01/GB)
- If one AZ's NAT Gateway fails, only that AZ is affected
- dev uses a single NAT to minimise cost during development

**Consequences:**
- (+) Production fault tolerance at the AZ level
- (+) No cross-AZ NAT data transfer costs in prod
- (-) 3x NAT Gateway cost in prod (~$0.045/hour each)
- (-) Different topology between environments

