# Troubleshooting Guide

A practical runbook for diagnosing and fixing common issues in this infrastructure.
Each entry includes symptoms, diagnosis commands, and fixes.

---

## Terraform Issues

### "couldn't find resource" on first apply

**Symptoms:**
Error: reading EKS Cluster: couldn't find resource

with data.aws_eks_cluster.this
**Diagnosis:**
The Kubernetes/Helm provider is trying to read the EKS cluster before it exists.

**Fix:**
Comment out the Kubernetes provider and data sources in `terraform.tf`, apply infra first, then uncomment and apply again:
```bash
# First apply — AWS resources only
terraform apply -auto-approve

# Then enable kubernetes provider and re-apply
terraform apply -auto-approve
```
Or use the split infra/platform module structure (recommended).

---

### "aws-auth ConfigMap does not exist"

**Symptoms:**
Error: The ConfigMap "aws-auth" does not exist

with module.eks.kubernetes_config_map_v1_data.aws_auth
**Diagnosis:**
The `aws-auth` ConfigMap is created by EKS only when the first node joins. The Terraform resource is trying to patch it before nodes are ready.

**Fix:**
Ensure the resource has `depends_on`:
```hcl
resource "kubernetes_config_map_v1_data" "aws_auth" {
  # ...
  depends_on = [aws_eks_node_group.main]
}
```
Update kubeconfig and re-apply:
```bash
aws eks update-kubeconfig --name platform-dev --region eu-central-1
terraform apply -auto-approve
```

---

### Terraform destroy hangs on namespace

**Symptoms:**
module.argocd.kubernetes_namespace.argocd: Still destroying... [10m elapsed]

Error: context deadline exceeded
**Diagnosis:**
ArgoCD finalizers are blocking namespace deletion.

**Fix:**
```bash
kubectl get namespace argocd -o json | \
  python3 -c "import sys,json; d=json.load(sys.stdin); d['spec']['finalizers']=[]; print(json.dumps(d))" | \
  kubectl replace --raw /api/v1/namespaces/argocd/finalize -f -
```

---

## Pod Issues

### ImagePullBackOff

**Symptoms:**
NAME                     READY   STATUS             RESTARTS

backend-xxx              0/1     ImagePullBackOff   0
**Diagnosis:**
```bash
kubectl describe pod -n backend <pod-name> | grep -A 5 "Events:"
```
Common causes: image does not exist in ECR, wrong tag, or ECR was deleted on destroy.

**Fix:**
Verify the image exists:
```bash
aws ecr list-images --repository-name platform-dev --region eu-central-1
```
If missing, rebuild and push:
```bash
aws ecr get-login-password --region eu-central-1 | \
  docker login --username AWS --password-stdin <account>.dkr.ecr.eu-central-1.amazonaws.com
docker build -t platform-backend apps/backend/
docker tag platform-backend:latest <ecr-url>:backend-v1.0.0
docker push <ecr-url>:backend-v1.0.0
```

---

### CreateContainerConfigError

**Symptoms:**
NAME                     READY   STATUS

backend-xxx              0/1     CreateContainerConfigError
**Diagnosis:**
A referenced Secret or ConfigMap does not exist.
```bash
kubectl get secret db-credentials -n backend
kubectl describe pod -n backend <pod-name>
```

**Fix:**
Check the ExternalSecret synced:
```bash
kubectl get externalsecret db-credentials -n backend
```
If `SecretSyncedError`, see the Secrets section below.

---

### CrashLoopBackOff

**Symptoms:**
NAME                     READY   STATUS             RESTARTS

backend-xxx              0/1     CrashLoopBackOff   7
**Diagnosis:**
```bash
kubectl logs -n backend <pod-name> --tail=30
```
Look for application errors — syntax errors, missing env vars, failed connections.

**Fix:**
Depends on the error. A common one in this project: invalid syntax from test comments added to `server.js`. Remove them, rebuild, and redeploy.

---

### Pod stuck in Pending

**Symptoms:**
NAME                     READY   STATUS

backend-xxx              0/1     Pending
**Diagnosis:**
```bash
kubectl describe pod -n backend <pod-name> | grep -A 5 "Events:"
```
Common causes:
- "Too many pods" → ENI/pod limit reached (add nodes)
- "no nodes available" → insufficient CPU/memory
- "no EC2 IMDS role" → EBS CSI IRSA missing (for PVCs)

**Fix:**
For pod limits, scale the node group. For PVC issues, verify the EBS CSI driver IRSA role.

---

## Readiness / Health Issues

### Pod Running but READY 0/1

**Symptoms:**
NAME                     READY   STATUS

backend-xxx              0/1     Running

**Diagnosis:**
Readiness probe is failing. Check the health endpoint:
```bash
kubectl exec -n backend <pod-name> -- wget -qO- http://localhost:8080/health
```
If it returns 503, the database connection is failing.

**Fix:**
See "Database connection failed" below.

---

## Secrets Issues

### ExternalSecret SecretSyncedError

**Symptoms:**
NAME             STORE                 STATUS              READY

db-credentials   aws-secrets-manager   SecretSyncedError   False
**Diagnosis:**
```bash
kubectl describe externalsecret db-credentials -n backend | grep -A 3 "Events:"
```

Common errors:
- `AccessDeniedException` → IRSA policy doesn't allow GetSecretValue
- `Secret does not exist` → wrong secret path for the environment

**Fix for AccessDenied:**
Verify the IRSA policy resource ARN matches:
```hcl
Resource = "arn:aws:secretsmanager:eu-central-1:028185488284:secret:platform/*"
```

**Fix for wrong path:**
Ensure the ExternalSecret references the correct environment path:
```bash
kubectl get externalsecret db-credentials -n backend -o yaml | grep "key:"
# Should show platform/stage/... for stage, not platform/dev/...
```

---

### ExternalSecret still reads old path after fix

**Symptoms:**
The manifest is correct in Git, but the cluster still uses the old path.

**Diagnosis:**
ArgoCD cache or the old ExternalSecret resource persists.

**Fix:**
```bash
kubectl delete externalsecret db-credentials -n backend
kubectl patch application secrets-config -n argocd \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

---

## Database Issues

### Database connection failed (503 on /health)

**Symptoms:**
```bash
$ kubectl exec -n backend <pod> -- wget -qO- http://localhost:8080/health
wget: server returned error: HTTP/1.1 503 Service Unavailable
```

**Diagnosis:**
Test the database connection directly:
```bash
kubectl run pg-test --image=postgres:17-alpine --restart=Never -n backend \
  --env="PGPASSWORD=<password>" \
  -- psql -h platform-db-rw.postgres.svc.cluster.local \
  -U platform -d platform -c "SELECT 1"
kubectl logs pg-test -n backend
```

If "password authentication failed", the password in Secrets Manager does not match the one CloudNativePG initialised with.

**Fix:**
Check the CloudNativePG password:
```bash
kubectl get secret platform-db-credentials -n postgres \
  -o jsonpath='{.data.password}' | base64 -d
```
Update Secrets Manager to match:
```bash
aws secretsmanager put-secret-value \
  --secret-id platform/stage/db-credentials \
  --secret-string '{"password":"<correct-password>",...}'
```
Force ESO sync and restart pods:
```bash
kubectl annotate externalsecret db-credentials -n backend force-sync=$(date +%s) --overwrite
kubectl delete pod -n backend --all
```

---

### postgres-cluster OutOfSync — CRD not found

**Symptoms:**
The Kubernetes API could not find postgresql.cnpg.io/Cluster
**Diagnosis:**
The CloudNativePG operator is not installed — its CRDs are missing.

**Fix:**
Ensure `cloudnative-pg.yaml` exists in the apps directory:
```bash
ls gitops/{env}/apps/ | grep cloudnative
```
If missing, add the operator Application and sync.

---

## CI/CD Issues

### OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity

**Symptoms:**

Error: Could not assume role with OIDC:

Not authorized to perform sts:AssumeRoleWithWebIdentity
**Diagnosis:**
- Wrong role ARN in GitHub secret
- Role does not exist (destroyed)
- aws-auth ConfigMap missing the role

**Fix:**
Verify the role exists and update the GitHub secret:
```bash
aws iam list-roles --query "Roles[?contains(RoleName,'github-actions')].Arn"
```
Update `AWS_ROLE_ARN` in GitHub → Settings → Secrets to the current environment's role.

---

### Helm: ownership metadata error

**Symptoms:**
Error: Service "backend" exists and cannot be imported:

missing key "app.kubernetes.io/managed-by": must be set to "Helm"

**Diagnosis:**
ArgoCD already created the resource; Helm cannot take ownership.

**Fix:**
```bash
kubectl annotate service backend -n backend \
  meta.helm.sh/release-name=backend \
  meta.helm.sh/release-namespace=backend --overwrite
kubectl label service backend -n backend \
  app.kubernetes.io/managed-by=Helm --overwrite
# Repeat for deployment
```

---

### Deploy job deploys to wrong cluster

**Symptoms:**

Error: No cluster found for name: platform-dev
**Diagnosis:**
The pipeline hardcodes a cluster name that no longer exists.

**Fix:**
Use branch-based cluster selection in the workflow:
```yaml
if [[ "${{ github.ref }}" == refs/heads/release/* ]]; then
  echo "name=platform-prod" >> $GITHUB_OUTPUT
else
  echo "name=platform-stage" >> $GITHUB_OUTPUT
fi
```

---

## Port-Forward Issues

### "address already in use"

**Symptoms:**
Unable to listen on port 8080: address already in use
**Diagnosis:**
A previous port-forward is still running.

**Fix:**
```bash
pkill -f "port-forward.*8080"
sleep 2
kubectl port-forward svc/backend 8080:8080 -n backend &
```

**Standard port convention for this project:**
8080 → backend

8081 → argocd

3000 → grafana

9090 → prometheus
---

## Cost / Cleanup Issues

### AWS still charging after destroy

**Diagnosis:**
Orphaned resources that Terraform did not manage.

**Fix:**
```bash
# Check clusters
aws eks list-clusters --region eu-central-1

# Check NAT gateways
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --region eu-central-1

# Check orphaned EBS volumes
aws ec2 describe-volumes --filters "Name=status,Values=available" --region eu-central-1

# Delete orphaned volume
aws ec2 delete-volume --volume-id vol-xxxxx --region eu-central-1
```

