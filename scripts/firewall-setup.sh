#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    . "$PROJECT_DIR/.env"
    set +a
fi

ALLOWED_SERVER_IPS="${ALLOWED_SERVER_IPS:?ALLOWED_SERVER_IPS is required in .env}"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

echo "Configuring UFW firewall..."

ufw --force reset

ufw default deny incoming
ufw default allow outgoing

echo "Allowing SSH (port 22)..."
ufw allow 22/tcp

IFS=',' read -ra IPS <<< "$ALLOWED_SERVER_IPS"
for IP in "${IPS[@]}"; do
    IP=$(echo "$IP" | xargs)
    if [ -n "$IP" ]; then
        echo "Allowing HTTP/HTTPS from ${IP}..."
        ufw allow from "$IP" to any port 80 proto tcp
        ufw allow from "$IP" to any port 443 proto tcp
    fi
done

ufw --force enable
ufw status verbose

echo ""
echo "Firewall configured successfully"
echo ""
echo "NOTE: Docker may bypass UFW rules by default."
echo "To prevent this, add to /etc/docker/daemon.json:"
echo '  { "iptables": false }'
echo "Then restart Docker: systemctl restart docker"
