# Mock VNF Server Dockerfile (Build2)
# Build: docker build -t mock-vnf:dev .
# Run:   docker run --rm -p 9443:9443 mock-vnf:dev

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Install only what's needed (Flask + requests)
RUN pip install --upgrade pip \
    && pip install flask>=2.3.0 requests>=2.31.0 pyyaml>=6.0.1

COPY mock_vnf_server.py ./

EXPOSE 9443

CMD ["python", "mock_vnf_server.py", "--vendor", "pfsense", "--port", "9443"]
