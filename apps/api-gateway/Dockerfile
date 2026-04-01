# ── Stage 1: builder ──────────────────────────────────────────────────────────
# We use a full slim image here to compile/install dependencies.
# This stage will NOT end up in the final image.
FROM python:3.11-slim AS builder

WORKDIR /app

# Copy only requirements first — this layer is cached until requirements.txt changes.
# If only main.py changes, Docker reuses this cached layer and skips reinstalling deps.
COPY requirements.txt .

RUN pip install --upgrade pip \
    && pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: runtime ──────────────────────────────────────────────────────────
# Fresh minimal image — no pip, no build tools, no cache. Just what we need to run.
FROM python:3.11-slim AS runtime

WORKDIR /app

# Copy installed packages from builder stage only — not the build toolchain
COPY --from=builder /install /usr/local

# Copy application source code
COPY main.py .

# Create a non-root user and group.
# Running as root inside a container is dangerous — if the process is exploited,
# the attacker gets root-level access. Kyverno will later enforce this at the cluster level.
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

USER appuser

# Document which port the app listens on (informational — does not publish it)
EXPOSE 8000

# Health check: Kubernetes liveness/readiness probes will later replace this,
# but it's good practice to define it here too for local/docker-compose use.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:8000/health').raise_for_status()"

# Run the app as a module — uvicorn is the ASGI server for FastAPI
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
