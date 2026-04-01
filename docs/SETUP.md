# SETUP.md
# ─────────────────────────────────────────────────────────────────────────────
# End-to-end setup guide — run these steps in order.
# Every command is meant to be understood, not just copy-pasted.
# ─────────────────────────────────────────────────────────────────────────────


# ── PREREQUISITES ─────────────────────────────────────────────────────────────
# Install these tools on your machine before starting.
#
#   Tool          Install
#   ───────────── ────────────────────────────────────────────
#   AWS CLI       https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html
#   Terraform     https://developer.hashicorp.com/terraform/install
#   kubectl       https://kubernetes.io/docs/tasks/tools/
#   Helm          https://helm.sh/docs/intro/install/
#   Docker        https://docs.docker.com/get-docker/
#   ArgoCD CLI    https://argo-cd.readthedocs.io/en/stable/cli_installation/
#   istioctl      https://istio.io/latest/docs/setup/getting-started/#download
#
# Configure AWS credentials:
aws configure
# Enter: Access Key ID, Secret Access Key, region (eu-west-1), output format (json)


# ═════════════════════════════════════════════════════════════════════════════
# PHASE 1 — INFRASTRUCTURE
# Provision the cloud resources: networking, Kubernetes cluster, image registry.
# ═════════════════════════════════════════════════════════════════════════════

# ── STEP 1: Bootstrap Terraform remote state ──────────────────────────────────
# This runs ONCE. Creates the S3 bucket and DynamoDB table that store
# all future Terraform state. Never run this again after the first time.

cd project4/infra/terraform/bootstrap
terraform init
terraform apply
# Note the outputs: state_bucket_name and dynamodb_table_name
# Paste both values into infra/terraform/versions.tf → backend "s3" block


# ── STEP 2: Deploy dev infrastructure ─────────────────────────────────────────
# Creates the VPC, EKS cluster, and ECR repositories for the dev environment.

cd project4/infra/terraform
terraform init

terraform workspace new dev
terraform workspace select dev
terraform apply
# This takes 15-20 minutes — EKS cluster creation is slow.

# Note the outputs:
#   cluster_name          → used in step 3
#   ecr_repository_urls   → paste these into helm/*/values-dev.yaml image.repository


# ── STEP 3: Deploy prod infrastructure ────────────────────────────────────────

terraform workspace new prod
terraform workspace select prod
terraform apply
# Note ecr_repository_urls for prod → paste into helm/*/values-prod.yaml


# ── STEP 4: Configure kubectl ─────────────────────────────────────────────────
# Download credentials so kubectl can talk to your EKS clusters.
# Do this for both clusters — switch between them with the --profile flag or
# by changing the current context.

aws eks update-kubeconfig --name platform-dev  --region eu-west-1
aws eks update-kubeconfig --name platform-prod --region eu-west-1

# Verify connection
kubectl get nodes


# ═════════════════════════════════════════════════════════════════════════════
# PHASE 2 — CLUSTER TOOLING
# Install the platform tools into both clusters.
# Run steps 5-8 once for dev, then again targeting the prod cluster.
# Switch clusters with: kubectl config use-context <context-name>
# List contexts with:   kubectl config get-contexts
# ═════════════════════════════════════════════════════════════════════════════

# ── STEP 5: Install Istio ─────────────────────────────────────────────────────
# Installs the Istio control plane and IngressGateway into the cluster.
# The 'demo' profile is fine for learning. Use 'default' for production.

istioctl install --set profile=demo -y

# Verify Istio pods are running
kubectl get pods -n istio-system

# Apply the namespace labels (enables sidecar injection in dev and prod)
kubectl apply -f project4/gitops/istio/namespace-labels.yaml

# Apply mTLS, Gateway, routing, and circuit breaker configs
kubectl apply -f project4/gitops/istio/peer-authentication.yaml
kubectl apply -f project4/gitops/istio/gateway.yaml
kubectl apply -f project4/gitops/istio/virtual-services.yaml
kubectl apply -f project4/gitops/istio/destination-rules.yaml


# ── STEP 6: Install Kyverno ───────────────────────────────────────────────────
# Installs the policy engine that enforces your security rules.

helm repo add kyverno https://kyverno.github.io/kyverno
helm repo update
helm install kyverno kyverno/kyverno -n kyverno --create-namespace

# Wait for Kyverno to be ready before applying policies
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kyverno \
  -n kyverno --timeout=120s

# Apply all policies
kubectl apply -f project4/policy/kyverno/

# Verify policies are active
kubectl get clusterpolicies


# ── STEP 7: Install ArgoCD ────────────────────────────────────────────────────

kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=180s

# Get the initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Open the ArgoCD UI (in a separate terminal)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit: https://localhost:8080  (username: admin, password: from above)


# ── STEP 8: Bootstrap GitOps with App of Apps ─────────────────────────────────
# Apply ONE file. ArgoCD reads the gitops/argocd/ folder and creates
# all 6 Applications (3 services × 2 environments) automatically.
# Update the repoURL in app-of-apps.yaml to your actual GitHub repo first.

kubectl apply -f project4/gitops/argocd/app-of-apps.yaml

# Watch ArgoCD create and sync all applications
kubectl get applications -n argocd -w


# ═════════════════════════════════════════════════════════════════════════════
# PHASE 3 — BUILD AND DEPLOY
# Build images, push to ECR, trigger deployments.
# ═════════════════════════════════════════════════════════════════════════════

# ── STEP 9: Authenticate Docker with ECR ─────────────────────────────────────
# ECR is a private registry — Docker needs credentials to push images.
# This token expires after 12 hours, so re-run it in new sessions.

aws ecr get-login-password --region eu-west-1 | \
  docker login --username AWS --password-stdin \
  123456789.dkr.ecr.eu-west-1.amazonaws.com
# Replace 123456789 with your actual AWS account ID


# ── STEP 10: Build and push images ────────────────────────────────────────────
# Repeat for each service. Replace ECR_URL with your actual ECR URLs
# from the Terraform outputs in Step 2/3.

ECR_URL="123456789.dkr.ecr.eu-west-1.amazonaws.com"

# api-gateway
docker build -t $ECR_URL/platform-dev-api-gateway:dev-latest \
  project4/apps/api-gateway/
docker push $ECR_URL/platform-dev-api-gateway:dev-latest

# user-service
docker build -t $ECR_URL/platform-dev-user-service:dev-latest \
  project4/apps/user-service/
docker push $ECR_URL/platform-dev-user-service:dev-latest

# order-service
docker build -t $ECR_URL/platform-dev-order-service:dev-latest \
  project4/apps/order-service/
docker push $ECR_URL/platform-dev-order-service:dev-latest


# ── STEP 11: Trigger ArgoCD sync ──────────────────────────────────────────────
# Dev syncs automatically once the image is in ECR.
# For prod, manually approve in the ArgoCD UI or via CLI:

argocd app sync api-gateway-prod
argocd app sync user-service-prod
argocd app sync order-service-prod


# ── STEP 12: Verify everything is running ─────────────────────────────────────

# Check pods are running (should see 2 containers each — app + Envoy sidecar)
kubectl get pods -n dev
kubectl get pods -n prod

# Check Kyverno hasn't blocked anything
kubectl get policyreport -A

# Check Istio sidecar injection worked (READY should show 2/2)
kubectl get pods -n dev -o wide

# Hit the gateway
kubectl get svc -n istio-system istio-ingressgateway


# ═════════════════════════════════════════════════════════════════════════════
# LOCAL DEVELOPMENT (no cluster needed)
# ═════════════════════════════════════════════════════════════════════════════

cd project4
docker compose up --build

# Test locally
curl localhost:8000/health
curl localhost:8000/users/1
curl localhost:8000/orders/1

docker compose down
