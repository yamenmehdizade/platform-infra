# Lessons Learned

Real problems encountered during this project, root causes, and fixes applied.
These are not sanitised — they reflect actual production-class issues.

---

## 1. Terraform Two-Phase Apply Problem

**Problem:**

Error: reading EKS Cluster: couldn't find resource

with data.aws_eks_cluster.this
**Root Cause:**
Helm and Kubernetes providers need to read the EKS cluster endpoint to configure themselves. On the first apply, EKS does not exist yet — the providers fail before any resources are created.

**Fix:**
Split the infrastructure into two Terraform root modules:
- `environments/{env}/infra/` — AWS resources only (VPC, EKS, IAM). No Helm/Kubernetes provider.
- `environments/{env}/platform/` — Helm resources (ArgoCD). Reads EKS endpoint from remote state.

```hcl
# platform/main.tf
data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "yamen-platform-tfstate-028185488284"
    key    = "dev/infra/terraform.tfstate"
    region = "eu-central-1"
  }
}
```

**What I learned:**
Terraform providers that depend on infrastructure outputs must be in a separate root module. This is also better for blast radius — an infra change does not risk destroying Helm releases.

---

## 2. PostgreSQL PVCs Stuck in Pending

**Problem:**
Warning ProvisioningFailed: failed to provision volume:

rpc error: no EC2 IMDS role found

**Root Cause:**
The EBS CSI driver creates EBS volumes in AWS. To do this, it needs AWS API credentials. The driver pod had no IAM role — it tried to use instance metadata (IMDS) and failed.

**Fix:**
Added an IRSA role for the EBS CSI controller service account:

```hcl
resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi"
  assume_role_policy = jsonencode({
    Statement = [{
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = 
            "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })
}
```

Also added the EKS managed add-on with the role ARN:
```hcl
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = var.ebs_csi_role_arn
}
```

**What I learned:**
Every AWS API call from a pod needs an IAM role. Never rely on node instance profiles for pod-level access — use IRSA. The error message "no EC2 IMDS role found" means the pod is falling back to instance metadata, which is a sign IRSA is not configured.

---

## 3. t3.medium Node Pod Limit (17 pods)

**Problem:**
Monitoring stack pods stuck in Pending:
Warning FailedScheduling: 0/2 nodes available: 2 Too many pods
**Root Cause:**
AWS limits the number of pods per node based on the EC2 instance's ENI (Elastic Network Interface) capacity. t3.medium supports 3 ENIs × 6 IPs = 17 pods maximum. With 17 system pods already scheduled (CoreDNS, kube-proxy, aws-node, etc.), no capacity remained.

**Fix:**
Added a third node. Also attempted VPC CNI prefix delegation (`ENABLE_PREFIX_DELEGATION=true`) which theoretically increases pod density, but the effect was minimal on t3.medium due to ENI count limits.

**What I learned:**
Instance type selection directly affects pod scheduling capacity, not just CPU/memory. In production, use at least m5.large (3 ENIs × 30 IPs = 58 pods) or enable prefix delegation on larger instances. Always calculate pod capacity before sizing node groups.

---

## 4. kube-prometheus-stack CRD Annotation Limit

**Problem:**
Error: context deadline exceeded

module.argocd.kubernetes_namespace.argocd: Still destroying...

**Root Cause:**
ArgoCD installs finalizers on its namespace (`resources-finalizer.argocd.argoproj.io`). When Terraform tries to delete the namespace, Kubernetes waits for ArgoCD to clean up its resources. But ArgoCD itself is being deleted — deadlock.

**Fix:**
Manually remove the finalizer using the Kubernetes raw API:
```bash
kubectl get namespace argocd -o json | \
  python3 -c "
    import sys, json
    d = json.load(sys.stdin)
    d['spec']['finalizers'] = []
    print(json.dumps(d))
  " | \
  kubectl replace --raw /api/v1/namespaces/argocd/finalize -f -
```

**What I learned:**
Kubernetes finalizers are a common source of stuck deletions. Always check for finalizers when a resource is stuck in `Terminating`. The pattern of patching the finalizer list to empty via the raw API is the standard fix. Added this to the destroy runbook.

---

## 6. GitHub Actions OIDC Authentication Failure

**Problem:**

Error: Could not assume role with OIDC:

Not authorized to perform sts:AssumeRoleWithWebIdentity

**Root Cause:**
The `aws-auth` ConfigMap in EKS did not include the GitHub Actions IAM role. Even though the OIDC trust policy was correct, EKS rejected the request because the role was not authorised to access the cluster.

**Fix:**
Added the GitHub Actions role to `aws-auth` via a Terraform `kubernetes_config_map_v1_data` resource:

```hcl
resource "kubernetes_config_map_v1_data" "aws_auth" {
  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.eks_node.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      {
        rolearn  = var.github_actions_role_arn
        username = "github-actions"
        groups   = ["system:masters"]
      }
    ])
  }
  force      = true
  depends_on = [aws_eks_node_group.main]
}
```

The `depends_on` is critical — `aws-auth` is created by EKS when the first node joins, so the resource must wait for the node group.

**What I learned:**
EKS authentication has two layers: AWS IAM (who can call the EKS API) and Kubernetes RBAC (what they can do inside the cluster). The `aws-auth` ConfigMap bridges these two systems. OIDC handles the AWS layer; `aws-auth` handles the Kubernetes layer.

---

## 7. Stage Secrets Pointing to Dev Path

**Problem:**
Warning UpdateFailed: error retrieving secret:

key: platform/dev/db-credentials, err: Secret does not exist

**Root Cause:**
The stage `ExternalSecret` manifest was copied from dev without updating the secret path. It was trying to read `platform/dev/db-credentials` in an environment where only `platform/stage/db-credentials` existed.

**Fix:**
Created environment-specific secret manifest directories:
apps/secrets/       ← dev ExternalSecret (platform/dev/...)

apps/secrets-stage/ ← stage ExternalSecret (platform/stage/...)

apps/secrets-prod/  ← prod ExternalSecret (platform/prod/...)

Each ArgoCD `secrets-config` Application points to the correct path for its environment.

**What I learned:**
When copying configuration between environments, always search for hardcoded environment-specific values. A grep for the environment name catches most of these:
```bash
grep -r "platform/dev" gitops/stage/
```
Consider using Helm templating or Kustomize for environment-specific values instead of separate directories.

---

## 8. EBS Volumes Not Deleted on Terraform Destroy

**Problem:**
After `terraform destroy`, AWS continued charging for EBS volumes.

**Root Cause:**
Kubernetes PersistentVolumeClaims create EBS volumes with a `ReclaimPolicy` of `Retain` (our gp3 StorageClass). When the cluster is destroyed, Terraform deletes the EKS cluster but has no visibility into EBS volumes created by Kubernetes. They remain as orphaned volumes.

**Fix:**
After every `terraform destroy`, manually check for orphaned volumes:
```bash
aws ec2 describe-volumes \
  --region eu-central-1 \
  --filters "Name=status,Values=available" \
  --query 'Volumes[].{ID:VolumeId,Size:Size}' \
  --output table
```

Delete orphaned volumes:
```bash
aws ec2 delete-volume --volume-id vol-xxxxxxxxx --region eu-central-1
```

**What I learned:**
Terraform only manages resources it created. Kubernetes-created AWS resources (EBS volumes, Load Balancers, Security Groups) are invisible to Terraform. Always verify with AWS CLI after destroy. Consider using `Delete` reclaim policy on StorageClasses for non-production environments.

---

## 9. PostgreSQL Password Mismatch Between Secrets Manager and CloudNativePG

**Problem:**
Backend health check returning 503 — database unreachable.
psql: FATAL: password authentication failed for user "platform"
**Root Cause:**
The CloudNativePG cluster initialised with `changeme123` (from the `platform-db-credentials` Kubernetes Secret). The stage Secrets Manager secret was created with `stage-changeme456`. The External Secrets Operator synced the wrong password to the backend pod.

**Fix:**
Update the Secrets Manager secret to match the password used by CloudNativePG:
```bash
aws secretsmanager put-secret-value \
  --secret-id platform/stage/db-credentials \
  --secret-string '{"password":"changeme123",...}'
```

Force ESO to re-sync:
```bash
kubectl annotate externalsecret db-credentials -n backend \
  force-sync=$(date +%s) --overwrite
```

Restart the backend pods to pick up the new Secret value.

**What I learned:**
When using an external operator to manage database credentials, the operator's secret and the database's initialisation secret must be in sync. In production, use a single secret source — generate the password once in Secrets Manager and reference it in both CloudNativePG and the application. Never hardcode credentials in Terraform variables.

---

## Summary

| # | Problem | Category | Key Takeaway |
|---|---------|----------|-------------|
| 1 | Two-phase apply | Terraform | Split infra and platform into separate root modules |
| 2 | EBS CSI no credentials | IRSA | Every pod that calls AWS needs its own IAM role |
| 3 | 17-pod node limit | Capacity | Instance type affects pod count, not just CPU/RAM |
| 4 | CRD annotation limit | ArgoCD | Not everything belongs in ArgoCD |
| 5 | Namespace finalizer | Kubernetes | Finalizers cause stuck deletions — know the fix |
| 6 | GitHub OIDC auth | EKS | aws-auth bridges IAM and Kubernetes RBAC |
| 7 | Wrong secret path | Multi-env | Always grep for hardcoded env names when copying configs |
| 8 | Orphaned EBS volumes | Cost | Kubernetes-created resources are invisible to Terraform |
| 9 | Password mismatch | Secrets | Single source of truth for credentials |

