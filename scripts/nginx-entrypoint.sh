#!/bin/sh
set -e

CONF_DIR="/etc/nginx/conf.d/dynamic"
ALLOWED_IPS_FILE="${CONF_DIR}/allowed_ips.conf"

TRUSTED_PROXIES_FILE="${CONF_DIR}/trusted_proxies.conf"

mkdir -p "$CONF_DIR"

if [ -n "$TRUSTED_PROXIES" ]; then
    > "$TRUSTED_PROXIES_FILE"
    echo "$TRUSTED_PROXIES" | tr ',' '\n' | while read -r cidr; do
        cidr=$(echo "$cidr" | xargs)
        if [ -n "$cidr" ]; then
            echo "set_real_ip_from ${cidr};" >> "$TRUSTED_PROXIES_FILE"
        fi
    done
    echo "real_ip_header X-Real-IP;" >> "$TRUSTED_PROXIES_FILE"
    echo "real_ip_recursive on;" >> "$TRUSTED_PROXIES_FILE"
    echo "Generated trusted_proxies.conf with $(grep -c set_real_ip_from "$TRUSTED_PROXIES_FILE") entries"
else
    > "$TRUSTED_PROXIES_FILE"
    echo "WARNING: TRUSTED_PROXIES not set, real_ip_header disabled"
fi

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
