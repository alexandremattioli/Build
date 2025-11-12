#!/bin/bash
# Generate RS256 keypair for VNF Broker JWT authentication

set -e

echo "=== VNF Broker RS256 Keypair Generation ==="
echo ""

# Generate private key (4096-bit RSA)
echo "Generating RSA private key..."
openssl genrsa -out vnf_broker_private.pem 4096

# Extract public key
echo "Extracting public key..."
openssl rsa -in vnf_broker_private.pem -pubout -out vnf_broker_public.pem

# Create Java-compatible public key (PKCS#8 format)
echo "Creating Java-compatible format..."
openssl pkcs8 -topk8 -inform PEM -outform DER -in vnf_broker_private.pem -out vnf_broker_private.der -nocrypt
openssl rsa -in vnf_broker_private.pem -pubout -outform DER -out vnf_broker_public.der

# Set secure permissions
chmod 600 vnf_broker_private.pem vnf_broker_private.der
chmod 644 vnf_broker_public.pem vnf_broker_public.der

echo ""
echo "[OK] Keypair generated successfully!"
echo ""
echo "Files created:"
echo "  - vnf_broker_private.pem (Python broker - KEEP SECURE)"
echo "  - vnf_broker_public.pem (CloudStack Java - distribute)"
echo "  - vnf_broker_private.der (Binary format)"
echo "  - vnf_broker_public.der (Binary format)"
echo ""
echo "Fingerprint (for verification):"
openssl rsa -in vnf_broker_private.pem -pubout -outform DER | sha256sum | awk '{print $1}'
echo ""
echo "SECURITY NOTES:"
echo "  1. Store vnf_broker_private.pem securely on broker host only"
echo "  2. Distribute vnf_broker_public.pem to CloudStack management server"
echo "  3. Never commit private keys to version control"
echo "  4. Rotate keys every 90 days"
