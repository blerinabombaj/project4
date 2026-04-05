# Kubernetes Troubleshooting Session — Interview Notes

## Problem 1 — Wrong Docker Tag Format (ImagePullBackOff)

### What happened
Running `docker build` and `docker push` with a doubled repository name in the tag:
```bash
ECR_URL="444062204470.dkr.ecr.eu-west-1.amazonaws.com/platform-prod-api-gateway"
docker build -t $ECR_URL/platform-prod-api-gateway:dev-latest apps/api-gateway/
```
This produced the tag:
```
444062204470.dkr.ecr.eu-west-1.amazonaws.com/platform-prod-api-gateway/platform-prod-api-gateway:dev-latest
```
Which doesn't exist in ECR. Also the build context path `project4/apps/api-gateway/` failed because we were already inside the `project4/` directory.

### Root cause
- `ECR_URL` already contained the repo name, then the repo name was appended again
- Build context path was relative to wrong directory

### Fix
```bash
ECR="444062204470.dkr.ecr.eu-west-1.amazonaws.com"
docker build -t $ECR/platform-prod-api-gateway:1.0.0 apps/api-gateway/
docker push $ECR/platform-prod-api-gateway:1.0.0
```
Pattern: `$ECR_BASE/<repo-name>:<tag>` — never nest the repo name inside `ECR_URL`.

### Interview talking point
> "I debugged an ImagePullBackOff by checking `kubectl describe pod` Events section, which showed the exact image URI the node was trying to pull. Comparing that to what was actually in ECR revealed a doubled repository name from incorrect variable interpolation in the build script."

---

## Problem 2 — Wrong CPU Architecture (no match for platform in manifest)

### What happened
Pods were in `ImagePullBackOff` with this exact error:
```
failed to pull and unpack image: no match for platform in manifest: not found
```

### Root cause
Images were built on a Mac with Apple Silicon (ARM64) but EKS nodes were `c7i-flex.large` (Intel x86_64/AMD64). The image manifest had no AMD64 layer — the node couldn't run it.

### How we diagnosed it
```bash
kubectl describe pod <pod-name> -n prod | grep -A 20 "Events:"
# Revealed: "no match for platform in manifest"
```

### Fix
Always build with `--platform linux/amd64` when targeting AWS:
```bash
docker build --platform linux/amd64 \
  -t $ECR/platform-prod-api-gateway:1.0.0 apps/api-gateway/
```

Or lock it permanently in the Dockerfile:
```dockerfile
FROM --platform=linux/amd64 python:3.11-slim
```

### Interview talking point
> "After ruling out IAM permissions and confirming the image existed in ECR, I found the real error in the pod Events: 'no match for platform in manifest'. The images were built on Apple Silicon (ARM64) but the EKS nodes were x86_64. Fixed by adding `--platform linux/amd64` to all docker build commands and locking it in the Dockerfile so it's enforced regardless of the build machine."

---

## Problem 3 — ECR IAM: Policy Attached to Wrong Role

### What happened
Even after attaching `AmazonEC2ContainerRegistryReadOnly` to `platform-prod-eks-node-role`, nodes were still failing to pull. Suspected the nodes were running under a different IAM role.

### How we diagnosed it
```bash
# Get the actual instance profile from a running node
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
INSTANCE_ID=$(kubectl get node $NODE_NAME \
  -o jsonpath='{.spec.providerID}' | cut -d'/' -f5)

aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region eu-west-1 \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn'
# Returned a UUID-named profile — not the expected role name

aws iam get-instance-profile \
  --instance-profile-name eks-16cead27-94ef-a4c4-8d4c-c6b21e2f68be \
  --query 'InstanceProfile.Roles[0].RoleName'
# Confirmed it WAS platform-prod-eks-node-role — so IAM was actually fine
```

### Root cause (turned out to be something else)
In this case the IAM was actually correct. The real issue was the image architecture mismatch (Problem 2). The diagnostic path is still valid and important.

### ECR Repository Policy
The project had an ECR resource-based policy (`aws_ecr_repository_policy` in Terraform) that explicitly whitelists the node role ARN. This is a second layer of access control on top of the IAM role policy. Both must be correct:
- IAM role on the node must have ECR read permissions
- ECR repository policy must allow that role's ARN in the `Principal`

### How it's defined in Terraform
```hcl
# modules/ecr/main.tf
resource "aws_ecr_repository_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEKSNodePull"
      Effect = "Allow"
      Principal = {
        AWS = var.eks_node_role_arn   # passed from module.eks.node_role_arn
      }
      Action = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ]
    }]
  })
}
```

### Interview talking point
> "I traced an ImagePullBackOff by getting the actual EC2 instance ID from the node's ProviderID, then checking which IAM instance profile was attached to that specific instance — not just what Terraform said should be there. This is important because Terraform state and actual AWS state can drift."

---

## Problem 4 — Istio Sidecars Not Injecting (1/1 instead of 2/2)

### What happened
All pods showed `1/1 Running` instead of `2/2 Running`. The Istio sidecar (`istio-proxy`) was not being injected.

### Root cause
The `istio-injection=enabled` label was missing from the `prod` and `dev` namespaces. Istio's mutating webhook only injects sidecars into pods in labeled namespaces.

### How we diagnosed it
```bash
kubectl get namespace prod dev --show-labels
# istio-injection label was absent
```

### Fix
```bash
kubectl label namespace prod istio-injection=enabled --overwrite
kubectl label namespace dev istio-injection=enabled --overwrite

# Restart pods so they get injected
kubectl rollout restart deployment -n prod
kubectl rollout restart deployment -n dev
```

### Interview talking point
> "Pods showing 1/1 instead of 2/2 is the immediate tell that Istio sidecars aren't injecting. The fix is to label the namespace with `istio-injection=enabled` and restart existing pods — new pods get the sidecar automatically but existing pods don't because the webhook only fires at pod creation time."

---

## Problem 5 — Kyverno Blocking Istio Sidecar Images

### What happened
After labeling namespaces and restarting deployments, pods failed to create with:
```
admission webhook "validate.kyverno.svc-fail" denied the request:
require-trusted-registry: Images must be pulled from the trusted ECR registry
```

### Root cause
The `require-trusted-registry` Kyverno ClusterPolicy blocked any image not from ECR. Istio injects two containers into every pod:
- `istio-proxy` (the Envoy sidecar) — pulled from a public registry
- `istio-init` (iptables init container) — also from a public registry

The Kyverno policy only had an `exclude` for the `istio-system` namespace, not for Istio-injected containers running in `dev`/`prod` namespaces.

### How we diagnosed it
```bash
kubectl describe replicaset api-gateway-prod-68db56cbcd -n prod
# Events showed full Kyverno denial message including which policy and rule failed
```

### Fix (immediate — unblocked for training)
Set the policy to `Audit` mode so violations are logged but not blocked:
```bash
kubectl patch clusterpolicy require-trusted-registry \
  --type merge \
  -p '{"spec":{"validationFailureAction":"Audit"}}'
```

### Fix (proper — for production)
Two options:

**Option A — Mirror Istio images to ECR (strongest security)**
```bash
# Pull Istio images and push to your ECR
docker pull istio/proxyv2:1.20.0
docker tag istio/proxyv2:1.20.0 \
  444062204470.dkr.ecr.eu-west-1.amazonaws.com/istio-proxy:1.20.0
docker push 444062204470.dkr.ecr.eu-west-1.amazonaws.com/istio-proxy:1.20.0

# Then configure Istio to pull from ECR instead of public registry
# in your IstioOperator or istioctl install config
```

**Option B — Allow Istio images in the policy pattern**
```yaml
validate:
  pattern:
    spec:
      containers:
        - image: "444062204470.dkr.ecr.eu-west-1.amazonaws.com/*"
      =(initContainers):
        - image: "444062204470.dkr.ecr.eu-west-1.amazonaws.com/* | *istio*"
```

### Why `background: false` was needed
Kyverno's background mode runs policy checks against existing resources using the Kyverno service account, which doesn't have `clusterRoles` context. Setting `background: false` disables retroactive scanning and only enforces at admission time — required when using `clusterRoles` in exclude rules.

### Interview talking point
> "Kyverno admission webhooks use `validate.kyverno.svc-fail` — the `-fail` suffix means it's a fail-closed webhook. If Kyverno itself is down or the webhook times out, pod creation is blocked. I debugged the denial by describing the ReplicaSet rather than the pod, because the pod never got created — the error lives at the ReplicaSet controller level. The fix required understanding the difference between the `istio-system` namespace exclusion (which we had) and excluding Istio-injected containers running in application namespaces (which we were missing)."

---

## Problem 6 — ArgoCD CLI Not Connected

### What happened
```
{"level":"fatal","msg":"Argo CD server address unspecified"}
```

### Root cause
The ArgoCD CLI wasn't logged in. It needs a server address and credentials on every new terminal session.

### Fix
```bash
# Port-forward ArgoCD server (keep this terminal open)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get the initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Login
argocd login localhost:8080 \
  --username admin \
  --password <password> \
  --insecure
```

### Interview talking point
> "The ArgoCD CLI is stateless between sessions — it stores the server address and token in `~/.config/argocd/config`. Any new terminal or after a port-forward dies requires re-login. In production you'd use an SSO-backed ArgoCD with a proper ingress so you're not relying on port-forwarding."

---

## General Debugging Workflow Learned

```
1. kubectl get pods -n <namespace>
        ↓ not Running?
2. kubectl describe pod <pod> -n <namespace> | grep -A 20 "Events:"
        ↓ admission webhook denied?
3. kubectl describe replicaset <rs> -n <namespace>
        ↓ (ReplicaSet events show the full webhook denial message)
        ↓ ImagePullBackOff?
4. Check exact error: "not found" vs "access denied" vs "no match for platform"
        ↓ "no match for platform" → architecture mismatch → --platform linux/amd64
        ↓ "access denied" → IAM issue → check node role + ECR repo policy
        ↓ "not found" → image doesn't exist in ECR → check ecr list-images
```

---

## Key Commands for Interviews

```bash
# Get exact pull error from a pod
kubectl describe pod <pod> -n <namespace> | grep -A 20 "Events:"

# Get exact webhook denial from a ReplicaSet
kubectl describe replicaset <rs> -n <namespace> | grep -A 10 "Warning"

# Check what IAM role a node is actually using
aws ec2 describe-instances \
  --instance-ids <id> \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn'

# Verify what's in an ECR repo
aws ecr list-images --repository-name <name> --region eu-west-1

# Check Kyverno policy violations without blocking
kubectl patch clusterpolicy <name> \
  --type merge \
  -p '{"spec":{"validationFailureAction":"Audit"}}'

# Check namespace labels (Istio injection)
kubectl get namespace <name> --show-labels

# Force pods to pick up new config (labels, policies, etc.)
kubectl rollout restart deployment -n <namespace>
```





---------



I'm continuing a Kubernetes training session. Here's my setup:
Cluster: AWS EKS, region eu-west-1, account 444062204470
Repo: https://github.com/blerinabombaj/project4
ECR: 444062204470.dkr.ecr.eu-west-1.amazonaws.com
Namespaces: dev and prod
Services: api-gateway (port 8000), user-service (port 8001), order-service (port 8002)
Image tags: all currently on 1.0.0
Stack installed: Istio (sidecars injecting, pods show 2/2), ArgoCD (app-of-apps pattern, prod is manual sync), Kyverno (require-trusted-registry set to Audit mode temporarily)
What's done:

Cluster is up, all pods 2/2 Running in both dev and prod
Images built with --platform linux/amd64 and pushed to ECR
ArgoCD managing 6 apps (3 services × 2 envs) via app-of-apps

Training plan — pick up at Module 1:

ArgoCD updates — change image tag in Helm values, ArgoCD syncs, watch rolling update, practice rollback
Everything green but app broken — simulate 500 errors, hung requests, shallow health checks
Istio traffic control — canary rollout with VirtualService weights, fault injection, ArgoCD Rollouts auto-rollback
Chaos Engineering — Chaos Mesh pod kill, network latency, CPU spike, combined experiment

Important notes:

Always build images with --platform linux/amd64 (Mac Apple Silicon → AWS x86_64 nodes)
Kyverno require-trusted-registry is in Audit mode — needs proper Istio image fix later
ArgoCD Rollouts not yet installed (needed for Module 3)
Chaos Mesh not yet installed (needed for Module 4)

Please confirm you understand the setup and start Module 1 Step 1.

Save that somewhere — it gives me everything I need to pick up exactly where we left off.