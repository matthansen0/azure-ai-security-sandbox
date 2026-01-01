# Build from upstream azure-search-openai-demo
# Clones the official repo at build time - no local code to maintain

FROM python:3.12-bookworm AS builder

# Install git and Node.js 20 for frontend build
RUN apt-get update && apt-get install -y git curl && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Clone the upstream repo
ARG UPSTREAM_REPO=https://github.com/Azure-Samples/azure-search-openai-demo.git
ARG UPSTREAM_REF=main
RUN git clone --depth 1 --branch ${UPSTREAM_REF} ${UPSTREAM_REPO} /src

# Build the frontend
WORKDIR /src/app/frontend
RUN npm install && npm run build

# Install Python dependencies
WORKDIR /src/app/backend
RUN pip install --no-cache-dir -r requirements.txt && pip install --no-cache-dir gunicorn

# --- Runtime stage ---
FROM python:3.12-slim-bookworm

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin/gunicorn /usr/local/bin/gunicorn

# Copy backend code (includes built frontend in /static, per vite.config.ts outDir)
COPY --from=builder /src/app/backend /app

EXPOSE 8000

CMD ["gunicorn", "-b", "0.0.0.0:8000", "-k", "uvicorn.workers.UvicornWorker", "main:app"]
