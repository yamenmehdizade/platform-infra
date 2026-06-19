# Threat Model

A structured threat model for this infrastructure, applying STRIDE methodology
and informed by 10+ years of network security experience.

---

## Methodology

This threat model uses **STRIDE**:
- **S**poofing — impersonating something or someone
- **T**ampering — modifying data or code
- **R**epudiation — claiming to not have performed an action
- **I**nformation Disclosure — exposing information to unauthorised parties
- **D**enial of Service — denying or degrading service
- **E**levation of Privilege — gaining capabilities without authorisation

---

## Trust Boundaries
┌─────────────────────────────────────────────┐

│  Internet (Untrusted)                        │

└──────────────────┬──────────────────────────┘

│  ← Trust Boundary 1: Edge

┌──────────────────▼──────────────────────────┐

│  WAF + ALB (DMZ)                             │

└──────────────────┬──────────────────────────┘

│  ← Trust Boundary 2: Network perimeter

┌──────────────────▼──────────────────────────┐

│  EKS Cluster (Private subnets)               │

│  ┌────────────────────────────────────────┐  │

│  │  Application Pods                      │  │

│  └─────────────────┬──────────────────────┘  │

│                    │  ← Trust Boundary 3: Pod-to-data

│  ┌─────────────────▼──────────────────────┐  │

│  │  PostgreSQL (Private DB subnet)        │  │

│  └────────────────────────────────────────┘  │

└──────────────────────────────────────────────┘

│  ← Trust Boundary 4: Cloud control plane

┌──────────────────▼──────────────────────────┐

│  AWS APIs (IAM, Secrets Manager, ECR)        │

└──────────────────────────────────────────────┘
---

## Threat Analysis by Component

### Edge (WAF + ALB)

| Threat | STRIDE | Mitigation |
|--------|--------|-----------|
| SQL injection attack | Tampering | WAF AWSManagedRulesSQLiRuleSet |
| XSS / OWASP Top 10 | Tampering | WAF AWSManagedRulesCommonRuleSet |
| DDoS / volumetric attack | DoS | WAF rate limiting (2000 req/5min), AWS Shield Standard |
| Known exploit payloads | Tampering | WAF AWSManagedRulesKnownBadInputsRuleSet |
| TLS downgrade | Info Disclosure | ALB enforces TLS 1.2+, HTTPS only |

### Network Layer

| Threat | STRIDE | Mitigation |
|--------|--------|-----------|
| Lateral movement between tiers | Elevation | 3-tier subnet isolation, Security Groups |
| Direct database access from internet | Info Disclosure | DB subnet has no route to IGW |
| Unauthorised east-west traffic | Tampering | Security Groups (stateful), NACLs (stateless) |
| Packet sniffing | Info Disclosure | VPC traffic is isolated; TLS in transit |

### Workload (Pods)

| Threat | STRIDE | Mitigation |
|--------|--------|-----------|
| Compromised pod accesses AWS | Elevation | IRSA — pod-scoped IAM, least privilege |
| Container escape | Elevation | Non-root containers, read-only root FS |
| Malicious image deployed | Tampering | Trivy scan in CI blocks CRITICAL CVEs |
| Pod-to-pod unauthorised access | Spoofing | NetworkPolicies (planned), namespace isolation |
| Secrets exposed in pod | Info Disclosure | ESO injects secrets at runtime, not in image |

### Data Layer

| Threat | STRIDE | Mitigation |
|--------|--------|-----------|
| Database credential theft | Info Disclosure | Secrets Manager, no secrets in Git |
| Data at rest exposure | Info Disclosure | EBS encryption at rest (KMS) |
| Unauthorised DB connection | Spoofing | DB in private subnet, password auth, SG rules |
| Backup data exposure | Info Disclosure | (Planned) encrypted backups |

### Cloud Control Plane

| Threat | STRIDE | Mitigation |
|--------|--------|-----------|
| Stolen CI/CD credentials | Spoofing | GitHub OIDC — no long-lived keys |
| Privilege escalation via IAM | Elevation | Least-privilege IAM policies, scoped to resources |
| Unauthorised cluster access | Spoofing | aws-auth ConfigMap, IAM authentication |
| Untracked admin actions | Repudiation | CloudTrail logging, GuardDuty analysis |

---

## Attack Scenarios

### Scenario 1: Compromised Container

**Attack:** An attacker exploits a vulnerability in the backend application and gains shell access to the pod.

**What the attacker CAN do:**
- Execute code within the container

**What the attacker CANNOT do:**
- Access AWS resources beyond the pod's IRSA role (Secrets Manager read only for its own secret)
- Access other pods' credentials (each has its own IRSA role)
- Escape to the node (non-root, read-only root FS)
- Reach the database without the correct credentials

**Defence in depth layers that contain this attack:**
1. IRSA limits AWS access to only what the pod needs
2. Network policies limit pod-to-pod traffic
3. GuardDuty detects anomalous API calls
4. Trivy would have flagged the vulnerability pre-deployment

### Scenario 2: Stolen GitHub Credentials

**Attack:** An attacker gains access to the GitHub repository.

**What the attacker CAN do:**
- Modify code and trigger the CI/CD pipeline

**What the attacker CANNOT do:**
- Extract long-lived AWS credentials (none exist — OIDC only)
- Deploy outside the configured branches (OIDC sub claim scoped)
- Bypass the Trivy security gate (CRITICAL CVEs block deployment)

**Detection:**
- CloudTrail logs all AssumeRoleWithWebIdentity calls
- Unusual deployment patterns visible in GitHub Actions history

### Scenario 3: DDoS Attack

**Attack:** Volumetric flood of requests to the application.

**Mitigation:**
1. WAF rate limiting drops IPs exceeding 2000 req/5min
2. AWS Shield Standard provides L3/L4 DDoS protection
3. ALB scales to absorb traffic
4. HPA (planned) scales backend pods under load

---

## Security Controls Mapped to CIS Benchmark

This infrastructure is monitored against the **CIS AWS Foundations Benchmark** via Security Hub:

| CIS Control | Implementation |
|-------------|---------------|
| CIS 1.x — IAM | Least-privilege IAM, IRSA, no root access keys |
| CIS 2.x — Logging | CloudTrail enabled, VPC Flow Logs |
| CIS 3.x — Monitoring | GuardDuty, Security Hub, CloudWatch |
| CIS 4.x — Networking | Security Groups, NACLs, no 0.0.0.0/0 ingress on sensitive ports |

---

## Residual Risks (Accepted)

| Risk | Why Accepted | Future Mitigation |
|------|-------------|-------------------|
| Self-managed PostgreSQL | Portfolio cost optimisation | Migrate to RDS in production |
| No NetworkPolicies yet | Time constraint | Implement Calico/Cilium policies |
| No Pod Security Admission | Time constraint | Enforce restricted PSS |
| Single-region deployment | Cost | Multi-region DR for production |
| No runtime threat detection | Not yet implemented | Add Falco for runtime security |

---

## Security Background Applied

My network security experience directly shaped this threat model:

- **Firewall mindset:** Security Groups are stateful firewall rules; NACLs are stateless ACLs. The same allow/deny logic from Palo Alto NGFWs applies.
- **Network segmentation:** The 3-tier subnet design mirrors enterprise DMZ/app/data zone separation.
- **Least privilege:** The IRSA model mirrors the principle of minimal firewall rules — grant only what is needed.
- **Defence in depth:** Multiple overlapping controls, so no single failure compromises the system.
- **Assume breach:** The threat model assumes a pod can be compromised and focuses on containment.

