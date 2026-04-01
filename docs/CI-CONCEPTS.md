# CI/CD CONCEPTS
# ─────────────────────────────────────────────────────────────────────────────
# Everything you need to understand about the pipeline before touching it.
# ─────────────────────────────────────────────────────────────────────────────


# ═════════════════════════════════════════════════════════════════════════════
# WHAT CI/CD ACTUALLY IS
# ═════════════════════════════════════════════════════════════════════════════
#
# CI — Continuous Integration
#   Every time a developer pushes code, an automated system builds it,
#   tests it, and checks it for problems. The goal is to catch issues
#   immediately — within minutes of a commit — rather than discovering
#   them days later when multiple people's changes have piled up.
#
#   Without CI: "Works on my machine" gets merged. Problems are found
#   in production. Nobody knows whose commit broke it.
#
#   With CI: Every commit is verified automatically. The pipeline is
#   the referee — it doesn't care who wrote the code.
#
# CD — Continuous Delivery / Continuous Deployment
#   The extension of CI into actually shipping the code.
#   Continuous Delivery: the pipeline prepares a release automatically,
#   but a human approves the final push to production.
#   Continuous Deployment: even that approval is automated.
#
#   This project uses Continuous Delivery:
#   Dev deploys automatically. Prod requires human approval.
#   That's a deliberate choice — speed in dev, control in prod.
#
# THE CORE IDEA:
#   Automate everything you do more than once.
#   Manual steps are where mistakes happen and where time is wasted.
#   The pipeline exists so the same process runs perfectly every time,
#   whether it's 2pm on a Tuesday or 11pm on a Friday.


# ═════════════════════════════════════════════════════════════════════════════
# GITHUB ACTIONS — THE BUILDING BLOCKS
# ═════════════════════════════════════════════════════════════════════════════
#
# GitHub Actions is the CI/CD platform built into GitHub.
# Your pipeline lives in .github/workflows/ as a YAML file.
# GitHub reads that file and runs it automatically based on triggers.
#
# ── WORKFLOWS ────────────────────────────────────────────────────────────────
#   A workflow is one YAML file. It defines when to run and what to do.
#   You can have multiple workflows — one for CI, one for releases,
#   one for scheduled tasks. They run independently.
#
# ── TRIGGERS (the `on:` block) ───────────────────────────────────────────────
#   Triggers define what causes the workflow to run.
#   Common triggers:
#
#   push:              runs when code is pushed to a branch
#   pull_request:      runs when a PR is opened or updated
#   workflow_dispatch: adds a "Run workflow" button in the GitHub UI
#                      — for manual runs with optional inputs
#   schedule:          runs on a cron schedule (e.g. nightly scans)
#
#   You can also filter triggers by branch or by which files changed.
#   In this project: the pipeline only runs when files in apps/ or helm/
#   change. A change to a README doesn't rebuild Docker images.
#
# ── JOBS ─────────────────────────────────────────────────────────────────────
#   A workflow is made up of jobs. Jobs run on a fresh virtual machine
#   (called a runner) each time. By default jobs run in parallel.
#
#   The `needs:` keyword creates a dependency between jobs.
#   In this project: update-dev-values needs build-and-scan to pass first.
#   If any build fails, the values file is never updated — nothing broken
#   makes it to the cluster.
#
# ── STEPS ────────────────────────────────────────────────────────────────────
#   Each job is a list of steps. Steps run in order, on the same machine.
#   A step is either a shell command (`run:`) or a pre-built action (`uses:`).
#
# ── ACTIONS ──────────────────────────────────────────────────────────────────
#   Actions are reusable building blocks written by GitHub or the community.
#   Instead of writing 20 lines of shell script to configure AWS credentials,
#   you use:  uses: aws-actions/configure-aws-credentials@v4
#   Actions live on GitHub and are versioned with @ — always pin to a version,
#   never use @main (it can change under you without warning).
#
# ── RUNNERS ──────────────────────────────────────────────────────────────────
#   The machine that runs your job. `ubuntu-latest` is a fresh Ubuntu VM
#   hosted by GitHub, thrown away after the job finishes. Nothing persists
#   between runs — every job starts clean. This is a feature, not a bug.
#   It means your build can't depend on leftover state from a previous run.


# ═════════════════════════════════════════════════════════════════════════════
# MATRIX STRATEGY — RUNNING ONE JOB MULTIPLE TIMES
# ═════════════════════════════════════════════════════════════════════════════
#
# You have three services. You could write the build job three times.
# Or you could write it once and use a matrix to run it in parallel
# for each service automatically.
#
# matrix:
#   service: [api-gateway, user-service, order-service]
#
# GitHub spins up three separate runners simultaneously, each with a
# different value of `matrix.service`. The job finishes 3x faster than
# running them in sequence.
#
# `fail-fast: false` means: if api-gateway's scan fails, keep running
# the scan for the other two. You want to see all problems at once,
# not fix one, run again, find the next one.


# ═════════════════════════════════════════════════════════════════════════════
# SECRETS AND ENVIRONMENT VARIABLES
# ═════════════════════════════════════════════════════════════════════════════
#
# Secrets are values that cannot be in your code — AWS credentials,
# passwords, API tokens. GitHub stores them encrypted and injects them
# into the pipeline at runtime as environment variables.
#
# You set them in: GitHub → your repo → Settings → Secrets and variables
#
# In the workflow they appear as: ${{ secrets.MY_SECRET }}
# GitHub masks them in logs — they never appear as plaintext.
#
# IMPORTANT: Never hardcode secrets in YAML files.
# Never print them with echo. Never commit them to Git.
# A secret committed to Git is compromised — even if you delete it,
# it's in the git history.
#
# ── GITHUB_TOKEN ─────────────────────────────────────────────────────────────
#   A special secret GitHub creates automatically for every run.
#   It gives the pipeline permission to interact with the repository —
#   read code, write comments on PRs, commit files back to the repo.
#   You don't need to create it. It exists by default.
#   Its permissions are controlled by the `permissions:` block.


# ═════════════════════════════════════════════════════════════════════════════
# OIDC AUTHENTICATION — NO STORED AWS KEYS
# ═════════════════════════════════════════════════════════════════════════════
#
# The old way: generate an AWS access key, store it in GitHub Secrets,
# use it in the pipeline. Problem: that key never expires. If GitHub
# is breached, the key works forever.
#
# The new way: OIDC (OpenID Connect).
# GitHub and AWS have a trust relationship. When the pipeline runs,
# GitHub generates a short-lived cryptographic token that proves
# "this request is coming from this repo, this branch, this workflow."
# AWS verifies the token and issues temporary credentials that expire
# when the job ends. Nothing to steal, nothing to rotate.
#
# The setup requires:
#   1. An OIDC provider configured in AWS IAM pointing at GitHub
#   2. An IAM role with a trust policy that only allows your specific
#      GitHub repo to assume it
#   3. The `id-token: write` permission in the workflow
#
# This is the current industry standard. If you see a project using
# long-lived AWS access keys in CI, that's a security problem to fix.


# ═════════════════════════════════════════════════════════════════════════════
# IMAGE TAGS — WHY THE COMMIT SHA
# ═════════════════════════════════════════════════════════════════════════════
#
# Every Docker image needs a tag — a label identifying which version it is.
# The tag choices matter more than they seem.
#
# ── `latest` ─────────────────────────────────────────────────────────────────
#   Everybody's first instinct. Don't use it in production.
#   `latest` means "the last thing pushed with no explicit tag."
#   It's not a version. It's not traceable. Two nodes can pull
#   `latest` at different times and get different images silently.
#   Kyverno blocks it in prod for exactly this reason.
#
# ── Semantic versions (v1.2.3) ───────────────────────────────────────────────
#   Human-readable and meaningful. Good for prod releases.
#   Requires someone to decide what the version number is.
#   In this project, prod tags come from the CI pipeline inputs
#   when a human triggers the prod promotion job.
#
# ── Git commit SHA (main-a1b2c3d) ────────────────────────────────────────────
#   What this pipeline uses for dev. The SHA is the identity of an
#   exact commit. If you see an image tagged main-a1b2c3d running
#   in dev, you can run `git show a1b2c3d` and see exactly what code
#   is in it. Perfect traceability, zero ambiguity.
#
# The short SHA (7 characters) is enough to be unique in any real repo.
# The `main-` prefix makes it obvious which branch it came from.


# ═════════════════════════════════════════════════════════════════════════════
# TRIVY — IMAGE SCANNING
# ═════════════════════════════════════════════════════════════════════════════
#
# Trivy is a vulnerability scanner. It inspects a Docker image and checks
# every package installed in it against a database of known CVEs
# (Common Vulnerabilities and Exposures).
#
# CVE SEVERITY LEVELS:
#   CRITICAL  →  exploitable, high impact, patch exists. Block the build.
#   HIGH      →  serious but may need context. Worth reviewing.
#   MEDIUM    →  limited scope. Track but don't block.
#   LOW       →  minimal risk. Informational.
#
# This pipeline fails on CRITICAL only. That's intentional.
# Failing on HIGH or MEDIUM would generate so many false positives
# that engineers start ignoring or disabling the scanner entirely —
# the worst outcome. Start strict on CRITICAL, expand scope over time.
#
# `ignore-unfixed: true` means: don't fail on vulnerabilities that have
# no available fix yet. There's nothing you can do about those right now.
# Focus on the ones you can actually fix.
#
# HOW IT CONNECTS TO THE PLATFORM:
#   Trivy runs in CI (before push) → only clean images reach ECR
#   ECR scan-on-push runs again (after push) → second check
#   Kyverno require-trusted-registry (at deploy) → only ECR images allowed
#   Three layers. An unsafe image has to get past all three.


# ═════════════════════════════════════════════════════════════════════════════
# THE GITOPS LOOP — HOW CI CONNECTS TO ARGOCD
# ═════════════════════════════════════════════════════════════════════════════
#
# This is the most important thing to understand about this pipeline.
#
# CI does NOT call ArgoCD. CI does NOT run helm upgrade.
# CI does NOT SSH into anything.
#
# CI writes a commit to Git. That's it.
#
# The loop works like this:
#
#   Developer pushes code
#        ↓
#   CI builds and scans the image
#        ↓
#   CI pushes image to ECR
#        ↓
#   CI commits a tag change to values-dev.yaml in Git
#        ↓
#   ArgoCD detects: "Git says tag should be main-a1b2c3d,
#                    cluster is running main-xyz9999. Diff found."
#        ↓
#   ArgoCD syncs: renders Helm chart with new tag, applies to cluster
#        ↓
#   Kubernetes performs a rolling update
#        ↓
#   New pods start, old pods terminate
#        ↓
#   Kyverno validates the new pods
#        ↓
#   Istio routes traffic to the new pods
#
# The pipeline's only job is to produce a clean image and record its
# tag in Git. Every tool downstream handles its own part automatically.
# This separation is why GitOps is powerful — each tool has one
# responsibility and does it well.
#
# ── THE [skip ci] TRICK ──────────────────────────────────────────────────────
#   When CI commits the values file back to Git, that commit would
#   normally trigger the pipeline again. The pipeline would build the
#   same image, commit again, trigger again — infinite loop.
#   Adding [skip ci] to the commit message tells GitHub Actions to
#   ignore that commit. One line prevents an infinite feedback loop.


# ═════════════════════════════════════════════════════════════════════════════
# ENVIRONMENTS AND APPROVAL GATES
# ═════════════════════════════════════════════════════════════════════════════
#
# GitHub Environments are named targets (dev, staging, production) with
# configurable protection rules. The prod promotion job uses the
# `production` environment, which you configure in:
# GitHub → Settings → Environments → production
#
# What you can configure:
#   Required reviewers    → specific people must approve before the job runs
#   Wait timer            → e.g. wait 10 minutes before deploying (time to cancel)
#   Deployment branches   → only the main branch can deploy to this environment
#
# When a job targeting a protected environment is triggered, GitHub
# pauses it and sends an approval request to the required reviewers.
# The job only runs after someone approves it.
#
# Combined with ArgoCD's manual prod sync, you have two independent
# approval gates before any change reaches production:
#   Gate 1: GitHub Environment approval (who can trigger the promotion)
#   Gate 2: ArgoCD manual sync (who can apply it to the cluster)


# ═════════════════════════════════════════════════════════════════════════════
# ARTIFACTS — SAVING PIPELINE OUTPUT
# ═════════════════════════════════════════════════════════════════════════════
#
# Artifacts are files generated during a pipeline run that you want to
# keep after the job finishes. Runners are ephemeral — everything on
# them disappears when the job ends.
#
# This pipeline saves Trivy scan results as an artifact.
# Even if the pipeline passes (no CRITICAL CVEs), you can still
# download the full report from the GitHub Actions UI and review
# HIGH or MEDIUM findings at your own pace.
#
# Artifacts are stored by GitHub for a configurable retention period
# (30 days in this project). After that they're automatically deleted.


# ═════════════════════════════════════════════════════════════════════════════
# THE FULL PICTURE — CI IN CONTEXT
# ═════════════════════════════════════════════════════════════════════════════
#
#  Developer pushes to a branch
#       ↓
#  PR opened → pipeline runs:
#    [build image] → [Trivy scan]
#    Fast feedback. No push. "Is this safe to merge?"
#       ↓
#  PR approved and merged to main → pipeline runs:
#    [build] → [Trivy scan] → [push to ECR] → [commit tag to Git]
#       ↓
#  ArgoCD auto-syncs dev
#       ↓
#  Engineer verifies dev is healthy
#       ↓
#  Engineer triggers workflow_dispatch with the commit SHA tag
#    → GitHub Environment approval gate
#    → CI updates values-prod.yaml in Git
#       ↓
#  ArgoCD detects prod diff but waits
#       ↓
#  Engineer clicks Sync in ArgoCD UI
#       ↓
#  Prod deploys
#
# Two humans, three tools, zero manual shell commands.
# Every step is logged, audited, and reproducible.
# That's the goal.
