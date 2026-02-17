#!/bin/sh
set -e

CONF_DIR="/etc/nginx/conf.d/dynamic"
ALLOWED_IPS_FILE="${CONF_DIR}/allowed_ips.conf"

mkdir -p "$CONF_DIR"

if [ -n "$CONSOLE_ALLOWED_IPS" ]; then
    > "$ALLOWED_IPS_FILE"
    echo "$CONSOLE_ALLOWED_IPS" | tr ',' '\n' | while read -r ip; do
        ip=$(echo "$ip" | xargs)
        if [ -n "$ip" ]; then
            echo "allow ${ip};" >> "$ALLOWED_IPS_FILE"
        fi
    done
    echo "Generated allowed_ips.conf with $(wc -l < "$ALLOWED_IPS_FILE") entries"
else
    echo "allow all;" > "$ALLOWED_IPS_FILE"
    echo "WARNING: CONSOLE_ALLOWED_IPS not set, allowing all access to console"
fi

exec nginx -g 'daemon off;'
