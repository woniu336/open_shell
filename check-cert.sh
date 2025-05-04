#!/bin/bash

# Enhanced OCSP Stapling & URI Checker

# Check if domain is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <domain>"
    exit 1
fi

DOMAIN=$1

# Check OCSP Stapling support
if openssl s_client -connect "${DOMAIN}":443 -servername "${DOMAIN}" -status < /dev/null 2>/dev/null | grep -q "OCSP response: no response sent"; then
    echo "OCSP Stapling: Not Enabled"
else
    echo "OCSP Stapling: Enabled"
fi

# Extract and show OCSP URI from certificate
OCSP_URI=$(echo | openssl s_client -connect "${DOMAIN}":443 -servername "${DOMAIN}" -showcerts 2>/dev/null | \
           openssl x509 -noout -ocsp_uri 2>/dev/null)

if [ -n "$OCSP_URI" ]; then
    echo "OCSP URI: $OCSP_URI"
else
    echo "OCSP URI: Not found"
fi
