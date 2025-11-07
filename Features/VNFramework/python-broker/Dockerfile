# VNF Broker Dockerfile (Build2)
# Build: docker build -t vnf-broker:dev .
# Run:   docker run --rm -p 8443:8443 -v $(pwd)/keys:/app/keys vnf-broker:dev

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# System deps
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements first for better layer caching
COPY requirements.txt ./
RUN pip install --upgrade pip \
    && pip install -r requirements.txt

# Copy application code
COPY vnf_broker_enhanced.py ./
COPY vnf_broker.py ./
COPY vnf_broker_redis.py ./
COPY dictionary_validator.py ./
COPY version_checker.py ./
COPY config.sample.json ./
COPY config.dev.json ./
COPY keys ./keys

# Expose broker port
EXPOSE 8443

# Healthcheck (optional simple TCP check)
HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD curl -sk https://localhost:8443/health || exit 1

# Default command
CMD ["python", "vnf_broker_enhanced.py"]
