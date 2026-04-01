# CONCEPTS.md
# ─────────────────────────────────────────────────────────────────────────────
# The "why" behind every folder in this project.
# Read this before touching any file. Read it again when something breaks.
# ─────────────────────────────────────────────────────────────────────────────


# ── THE BIG PICTURE ──────────────────────────────────────────────────────────
#
# This project answers one question:
#   "How do you take code on a developer's laptop and get it running
#    reliably, securely, and automatically in the cloud?"
#
# Most juniors can write code. Mid-level engineers understand the
# infrastructure, automation, and safety systems around that code.
# That gap is exactly what this project covers.
#
# Every folder solves one specific problem in that journey:
#
#   apps/          →  package the code into a portable unit (container)
#   docker-compose →  run everything locally before touching the cloud
#   helm/          →  describe how to run containers in Kubernetes
#   infra/         →  provision the cloud resources to run it all on
#   policy/        →  enforce rules so nothing unsafe can run
#   gitops/argocd  →  automate deployments from Git
#   gitops/istio   →  control and secure all network traffic
#
# These aren't independent tools. Each one builds on the previous.
# Remove any one of them and a real gap opens up.


# ═════════════════════════════════════════════════════════════════════════════
# DOCKER  (apps/ + Dockerfile)
# ═════════════════════════════════════════════════════════════════════════════
#
# PROBLEM IT SOLVES:
#   "It works on my machine" is the oldest problem in software.
#   Different machines have different OS versions, Python versions,
#   library versions. Code that works in dev breaks in production.
#
# WHAT DOCKER DOES:
#   A container packages your code AND everything it needs to run —
#   the runtime, the libraries, the config — into one portable unit.
#   That unit runs identically everywhere: your laptop, CI, the cloud.
#
# THE DOCKERFILE:
#   A recipe. "Start with this base image, copy these files, install
#   these dependencies, run as this user, start with this command."
#   The result is an image — a frozen, versioned snapshot of your app.
#
# THE SECURITY ANGLE:
#   We deliberately shrink the image (multi-stage build), run as a
#   non-root user, and make the filesystem read-only. A smaller image
#   has fewer vulnerabilities. A non-root process limits what an
#   attacker can do if they break in.
#
# HOW IT CONNECTS FORWARD:
#   The image built from the Dockerfile is pushed to ECR (the registry),
#   pulled by Kubernetes (the orchestrator), and must pass Kyverno's
#   security checks before it's allowed to run.


# ═════════════════════════════════════════════════════════════════════════════
# DOCKER COMPOSE  (docker-compose.yaml)
# ═════════════════════════════════════════════════════════════════════════════
#
# PROBLEM IT SOLVES:
#   You have three services. Running three separate docker commands,
#   managing their network connections, waiting for one to start before
#   another — that's tedious and error-prone.
#
# WHAT DOCKER COMPOSE DOES:
#   Defines and runs multi-container applications with a single command.
#   It handles networking (services find each other by name), startup
#   order (wait for healthcheck to pass before starting the next), and
#   shared configuration.
#
# WHY IT MATTERS FOR LEARNING:
#   Docker Compose is your local rehearsal for Kubernetes. The same
#   concepts — services talking to each other, health checks, environment
#   variables — exist in both. Compose is just simpler and faster to run.
#   You iterate here before deploying to the cluster.
#
# HOW IT CONNECTS FORWARD:
#   Compose is only for local development. Once code goes to the cluster,
#   Helm and Kubernetes take over. The mental model stays the same;
#   the tooling changes.


# ═════════════════════════════════════════════════════════════════════════════
# KUBERNETES + HELM  (helm/)
# ═════════════════════════════════════════════════════════════════════════════
#
# PROBLEM IT SOLVES (KUBERNETES):
#   Containers on a single machine isn't enough for production.
#   You need: multiple machines for redundancy, automatic restarts when
#   containers crash, rolling updates without downtime, and traffic
#   load balancing across multiple copies of your service.
#   Kubernetes does all of this.
#
# WHAT KUBERNETES DOES:
#   It's a container orchestrator. You tell it "I want 3 copies of
#   this container running at all times" and Kubernetes makes it happen —
#   scheduling them across machines, restarting failures, routing traffic.
#   You describe the desired state; Kubernetes continuously works to
#   match reality to that description.
#
# PROBLEM IT SOLVES (HELM):
#   Kubernetes is configured with YAML files. Those files are nearly
#   identical between dev and prod — same structure, different values
#   (replica count, image tag, resource limits). Copy-pasting and
#   manually editing YAML for every environment is how mistakes happen.
#
# WHAT HELM DOES:
#   Helm is a templating layer on top of Kubernetes YAML. You write the
#   structure once, and environment-specific values (dev vs prod) fill
#   in the blanks at deploy time. One chart, many environments, no
#   duplication.
#
# HOW IT CONNECTS FORWARD:
#   Helm charts are what ArgoCD deploys. ArgoCD reads your chart from
#   Git and applies it to the cluster. Kyverno then inspects every
#   resource Helm creates and blocks anything that violates policy.


# ═════════════════════════════════════════════════════════════════════════════
# TERRAFORM  (infra/)
# ═════════════════════════════════════════════════════════════════════════════
#
# PROBLEM IT SOLVES:
#   Before your app can run anywhere, the infrastructure must exist —
#   the network, the servers, the container registry, the Kubernetes
#   cluster. Clicking through the AWS console to create these by hand
#   is slow, error-prone, and impossible to reproduce exactly.
#
# WHAT TERRAFORM DOES:
#   Infrastructure as Code. You describe the infrastructure you want
#   in code files, and Terraform talks to AWS to make it real.
#   The same code run twice produces the same infrastructure every time.
#   It also tracks what it created, so it knows what to change or delete.
#
# THE BOOTSTRAP PROBLEM:
#   Terraform stores a record of what it built (called "state") in a
#   file. That file needs to live somewhere safe and shared — an S3
#   bucket. But Terraform can't create the S3 bucket using itself,
#   because the bucket doesn't exist yet. Bootstrap solves this by
#   running once with local state to create the bucket, then all
#   future runs store state there.
#
# WORKSPACES (dev vs prod):
#   Instead of duplicating all the infrastructure code for dev and prod,
#   workspaces let you run the same code twice with a different name
#   active. Dev gets smaller, cheaper resources. Prod gets larger,
#   more resilient resources. One codebase, two environments.
#
# MODULES:
#   Reusable blocks of infrastructure. The ECR module creates one image
#   repository. We call it three times (once per service) instead of
#   writing the same resource block three times.
#
# HOW IT CONNECTS FORWARD:
#   Terraform creates the EKS cluster that Kubernetes runs on, and the
#   ECR repositories that store Docker images. Everything else in this
#   project assumes these exist.


# ═════════════════════════════════════════════════════════════════════════════
# KYVERNO  (policy/)
# ═════════════════════════════════════════════════════════════════════════════
#
# PROBLEM IT SOLVES:
#   Best practices written in documentation get ignored.
#   A new team member deploys a container running as root with no
#   resource limits, using an image from a random public registry.
#   Without enforcement, nothing stops this from happening in production.
#
# WHAT KYVERNO DOES:
#   Kyverno is a policy engine that sits inside Kubernetes. Every time
#   anyone tries to create or update a resource, Kyverno inspects it
#   against a set of rules before it's allowed to run. If it fails a
#   rule, the request is blocked — the container never starts.
#
# WHAT IT ENFORCES IN THIS PROJECT:
#   - No container runs as root
#   - Every container must declare resource limits
#   - The filesystem must be read-only
#   - Images must come from your private ECR registry only
#   - Production cannot use the "latest" tag
#
# WHY THIS MATTERS:
#   The Dockerfile and Helm values already set these things correctly.
#   Kyverno is the safety net for when someone creates a resource
#   that bypasses those files — a raw kubectl command, a one-off debug
#   pod, an automated tool that doesn't follow your conventions.
#
# HOW IT CONNECTS FORWARD:
#   Kyverno and Istio are complementary. Kyverno controls WHAT can run
#   (admission time). Istio controls HOW running services communicate
#   (runtime). Together they cover the full security surface.


# ═════════════════════════════════════════════════════════════════════════════
# ARGOCD  (gitops/argocd/)
# ═════════════════════════════════════════════════════════════════════════════
#
# PROBLEM IT SOLVES:
#   Deploying manually — running helm upgrade by hand, SSHing into
#   servers, running scripts — is slow, inconsistent, and leaves no
#   audit trail. Who deployed what, when, and did it match what's in Git?
#
# WHAT GITOPS MEANS:
#   Git is the single source of truth for what should be running.
#   If it's in Git, it runs. If it's not in Git, it doesn't run.
#   Any change to the cluster goes through a Git commit first —
#   reviewed, approved, and tracked like any other code change.
#
# WHAT ARGOCD DOES:
#   ArgoCD watches your Git repository. When it detects a difference
#   between what Git says should be running and what's actually running
#   in the cluster, it syncs them. It's a continuous reconciliation loop.
#   You don't push to the cluster — you push to Git, and ArgoCD handles
#   the rest.
#
# DEV vs PROD PROMOTION:
#   Dev syncs automatically — fast feedback, rapid iteration.
#   Prod requires a human to approve the sync — a deliberate gate
#   before changes reach users. You prove it works in dev first,
#   then promote to prod with intent.
#
# THE APP OF APPS PATTERN:
#   Rather than registering each service with ArgoCD individually,
#   one parent application watches the gitops/argocd/ folder. ArgoCD
#   sees the Application files there and manages them automatically.
#   Adding a new service is a Git commit, not a manual setup step.
#
# HOW IT CONNECTS FORWARD:
#   ArgoCD is the delivery mechanism. Helm defines the package,
#   Terraform provides the cluster, Kyverno enforces the rules,
#   and ArgoCD is what actually gets the package onto the cluster.


# ═════════════════════════════════════════════════════════════════════════════
# ISTIO  (gitops/istio/)
# ═════════════════════════════════════════════════════════════════════════════
#
# PROBLEM IT SOLVES:
#   Inside a Kubernetes cluster, services talk to each other over plain
#   HTTP. Any compromised service can freely call any other. There is no
#   encryption, no identity verification, and no way to see what's
#   happening without modifying application code.
#
# WHAT A SERVICE MESH DOES:
#   Istio injects a small proxy (Envoy) alongside every container.
#   This proxy intercepts all network traffic — in and out — without
#   the application knowing. The mesh handles encryption, routing,
#   retries, timeouts, and observability at the infrastructure level,
#   not the application level. Your app code changes nothing.
#
# THE FOUR THINGS ISTIO GIVES YOU:
#
#   1. mTLS (Zero Trust Networking)
#      Every service gets a cryptographic identity. Services verify
#      each other before any request goes through. A compromised pod
#      with no valid certificate gets rejected automatically. Traffic
#      is encrypted between every service, even inside the cluster.
#
#   2. Traffic Control
#      The Gateway is the single door into your cluster from the
#      internet. VirtualServices are the routing rules inside — which
#      URL goes to which service, with what timeout.
#
#   3. Circuit Breaking
#      If a service starts returning errors, Istio stops sending
#      traffic to it and routes to healthy instances instead. This
#      prevents one failing service from cascading and taking down
#      everything that depends on it.
#
#   4. Observability
#      Because all traffic flows through Envoy, Istio can measure
#      latency, error rates, and request volumes for every service
#      automatically — no instrumentation needed in the app code.
#
# HOW IT CONNECTS BACK:
#   Istio is the last layer of the security model.
#   Kyverno ensures only safe containers run.
#   Istio ensures those containers can only communicate safely.
#   Together they mean: nothing unsafe runs, and nothing runs unsafely.


# ═════════════════════════════════════════════════════════════════════════════
# HOW EVERYTHING CONNECTS — THE FULL PICTURE
# ═════════════════════════════════════════════════════════════════════════════
#
#  You write code
#       ↓
#  Docker packages it into an image  (apps/)
#       ↓
#  You test it locally               (docker-compose.yaml)
#       ↓
#  Terraform builds the cloud infra  (infra/)
#  — VPC, EKS cluster, ECR registry
#       ↓
#  You push the image to ECR
#  Trivy scans it for vulnerabilities
#       ↓
#  You commit a Helm values change to Git  (helm/)
#       ↓
#  ArgoCD detects the change in Git  (gitops/argocd/)
#  and applies the Helm chart to the cluster
#       ↓
#  Kyverno inspects every resource   (policy/)
#  and blocks anything that violates policy
#       ↓
#  Pods start — Istio injects Envoy sidecars  (gitops/istio/)
#  mTLS is enforced between all services
#  Gateway routes external traffic in
#  Circuit breakers protect against cascading failures
#       ↓
#  Your code is running in production.
#  Securely. Automatically. Verifiably.
