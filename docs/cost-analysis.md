# Cost Analysis

Real cost data and optimisation strategies from running this infrastructure.
All figures are for AWS eu-central-1 (Frankfurt) and reflect actual observed costs.

---

## Cost Breakdown per Component

### EKS Control Plane
| Item | Cost |
|------|------|
| EKS cluster control plane | $0.10/hour = ~$73/month |

The control plane cost is fixed per cluster, regardless of node count. This is the same for dev, stage, and prod.

### Compute (EC2 Worker Nodes)
| Instance Type | Hourly | Daily | Monthly (per node) |
|--------------|--------|-------|-------------------|
| t3.medium | $0.0456 | ~$1.10 | ~$33 |
| t3.large | $0.0912 | ~$2.19 | ~$66 |
| m5.xlarge | $0.23 | ~$5.52 | ~$166 |

### NAT Gateway
| Item | Cost |
|------|------|
| NAT Gateway (per gateway) | $0.045/hour = ~$33/month |
| NAT data processing | $0.045/GB |

### EBS Volumes (gp3)
| Item | Cost |
|------|------|
| gp3 storage | $0.08/GB/month |
| 10GB PostgreSQL PVC | ~$0.80/month |

### Other Services
| Service | Cost |
|---------|------|
| WAF WebACL | $5.00/month + $1.00 per rule + $0.60 per million requests |
| GuardDuty | ~$4.00/month (varies with event volume) |
| Security Hub | $0.0010 per finding ingested |
| Secrets Manager | $0.40/secret/month + $0.05 per 10,000 API calls |
| S3 (state) | Negligible (<$0.10/month) |
| DynamoDB (lock) | Negligible (on-demand, minimal usage) |

---

## Monthly Cost per Environment (if left running 24/7)

### Dev Environment

EKS control plane          $73

3x t3.medium nodes         $99

1x NAT Gateway             $33

EBS volumes (~20GB)        $2

WAF                        $7

GuardDuty                  $4

Secrets Manager            $1

─────────────────────────────

Total                      ~$219/month

### Stage Environment
EKS control plane          $73

2x t3.large nodes          $132

2x NAT Gateway             $66

EBS volumes                $2

WAF                        $7

GuardDuty                  $4

Secrets Manager            $1

─────────────────────────────

Total                      ~$285/month

### Production Environment
EKS control plane          $73

3x m5.xlarge nodes         $498

3x NAT Gateway             $99

EBS volumes                $5

WAF                        $7

GuardDuty                  $4

Secrets Manager            $1

─────────────────────────────

Total                      ~$687/month

### All Three Environments Running
Dev    ~$219

Stage  ~$285

Prod   ~$687

─────────────

Total  ~$1,191/month
---

## Actual Portfolio Costs (Apply → Test → Destroy)

This project is **not** run 24/7. The workflow is:
1. `terraform apply` (~20 min)
2. Test and capture screenshots (~1-2 hours)
3. `terraform destroy`

### Observed Real Costs

| Session | Duration | Environment | Observed Cost |
|---------|----------|-------------|--------------|
| Dev build | ~5 hours | dev (t3.medium) | ~$5 |
| Stage build | ~4 hours | stage (t3.large) | ~$6 |
| Prod build | ~5 hours | prod (m5.xlarge) | ~$15 |

### June 2026 Monthly Total (observed)

EC2 Compute               $6.09

EC2 Other (EBS, NAT)      $6.03

EKS Control Plane         $2.61

WAF                       $0.22

VPC                       $0.19

─────────────────────────────

Total                     ~$15
The entire month of intermittent development cost approximately **$15-40**, compared to ~$1,191/month if all environments ran continuously.

---

## Cost Optimisation Strategies Applied

### 1. Destroy After Every Session
The single most effective optimisation. Running clusters only during active work reduces cost by ~95%.

### 2. Verify Orphaned Resources
Kubernetes-created EBS volumes survive `terraform destroy`. Always check:
```bash
aws ec2 describe-volumes --filters "Name=status,Values=available" \
  --query 'Volumes[].VolumeId' --output text
```

### 3. Single NAT Gateway in Dev
Dev uses 1 NAT Gateway instead of 3, saving ~$66/month when running.

### 4. Right-Sized Instances for Portfolio Work
Use t3.medium for portfolio demonstrations. The architecture is identical — only the instance type differs. m5.xlarge in prod is for demonstrating production sizing, not for extended running.

### 5. Spot Instances (Future)
For non-critical workloads, Spot instances can reduce compute cost by up to 70%. Not yet implemented in this project.

---

## Cost Monitoring Commands

### Current month costs by service
```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-06-01,End=2026-06-30 \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --output json
```

### Check for running clusters
```bash
aws eks list-clusters --region eu-central-1
```

### Check for active NAT Gateways
```bash
aws ec2 describe-nat-gateways \
  --filter "Name=state,Values=available" \
  --region eu-central-1
```

### Check for orphaned volumes
```bash
aws ec2 describe-volumes \
  --filters "Name=status,Values=available" \
  --region eu-central-1
```

---

## Production Cost Optimisation Recommendations

For a real production deployment, these would reduce costs significantly:

| Strategy | Potential Saving |
|----------|-----------------|
| Reserved Instances / Savings Plans | Up to 72% on compute |
| Spot for stateless workloads | Up to 70% on those nodes |
| VPC Endpoints (S3, ECR) | Reduces NAT data transfer |
| Karpenter for node autoscaling | Right-sizes nodes dynamically |
| Single NAT Gateway + retry logic | ~$66/month per removed gateway |
| Graviton (ARM) instances | ~20% better price/performance |

---

## Key Takeaway

The most important cost lesson from this project: **EKS control plane + NAT Gateways are fixed costs that accrue 24/7 whether or not you use the cluster.** For portfolio and learning purposes, the apply-test-destroy workflow keeps monthly costs under $40 while still demonstrating production-grade architecture.

