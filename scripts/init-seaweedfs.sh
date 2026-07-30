#!/bin/sh
set -e

apk add --no-cache jq openssl >/dev/null 2>&1

CONFIG_DIR=/etc/seaweedfs
CONFIG_FILE="$CONFIG_DIR/identities.json"
mkdir -p "$CONFIG_DIR"

ALL_BUCKETS="${ACERVO_BUCKETS:?ACERVO_BUCKETS is required}"
PUBLIC_BUCKETS="${ACERVO_PUBLIC_BUCKETS:-portal mapalab iieg}"
ADMIN_AK="${ACERVO_ADMIN_ACCESS_KEY:?ACERVO_ADMIN_ACCESS_KEY is required}"
ADMIN_SK="${ACERVO_ADMIN_SECRET_KEY:?ACERVO_ADMIN_SECRET_KEY is required}"
ROTATE_FLAG="${ROTATE_FLAG:-0}"
TARGET_BUCKET="${TARGET_BUCKET:-}"

if [ -n "$TARGET_BUCKET" ]; then
    VALID=0
    for b in $ALL_BUCKETS; do
        [ "$b" = "$TARGET_BUCKET" ] && VALID=1
    done
    if [ "$VALID" != "1" ]; then
        echo "ERROR: Bucket '$TARGET_BUCKET' no esta en ACERVO_BUCKETS ($ALL_BUCKETS)" >&2
        exit 1
    fi
fi

randstr() {
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 32
}

get_existing_secret() {
    user="$1"
    if [ -f "$CONFIG_FILE" ]; then
        jq -r --arg u "$user" '.identities[]? | select(.name == $u) | .credentials[0].secretKey // empty' "$CONFIG_FILE" 2>/dev/null || echo ""
    fi
}

TMP=$(mktemp)
cat > "$TMP" <<EOF
{
  "identities": [
    {
      "name": "admin",
      "credentials": [
        {"accessKey": "$ADMIN_AK", "secretKey": "$ADMIN_SK"}
      ],
      "actions": ["Admin", "Read", "Write", "List", "Tagging"]
    }
  ]
}
EOF

PRINTED=""

for BUCKET in $ALL_BUCKETS; do
    USER="${BUCKET}-user"
    EXISTING=$(get_existing_secret "$USER")

    ROTATE_THIS=0
    if [ -z "$EXISTING" ]; then
        ROTATE_THIS=1
    elif [ "$ROTATE_FLAG" = "1" ]; then
        if [ -z "$TARGET_BUCKET" ] || [ "$TARGET_BUCKET" = "$BUCKET" ]; then
            ROTATE_THIS=1
        fi
    fi

    if [ "$ROTATE_THIS" = "1" ]; then
        SECRET=$(randstr)
        PRINTED="${PRINTED}
==========================================
  Bucket:    $BUCKET
  AccessKey: $USER
  SecretKey: $SECRET
=========================================="
    else
        SECRET="$EXISTING"
    fi

    ACTIONS=$(printf '["Admin:%s", "Read:%s", "Write:%s", "List:%s", "Tagging:%s"]' \
        "$BUCKET" "$BUCKET" "$BUCKET" "$BUCKET" "$BUCKET")

    jq --arg name "$USER" \
       --arg ak "$USER" \
       --arg sk "$SECRET" \
       --argjson actions "$ACTIONS" \
       '.identities += [{
         "name": $name,
         "credentials": [{"accessKey": $ak, "secretKey": $sk}],
         "actions": $actions
       }]' "$TMP" > "${TMP}.new"
    mv "${TMP}.new" "$TMP"
done

ANON_ACTIONS="["
FIRST=1
for PB in $PUBLIC_BUCKETS; do
    [ "$FIRST" = "1" ] || ANON_ACTIONS="${ANON_ACTIONS},"
    ANON_ACTIONS="${ANON_ACTIONS}\"Read:${PB}\""
    FIRST=0
done
ANON_ACTIONS="${ANON_ACTIONS}]"

if [ "$ANON_ACTIONS" != "[]" ]; then
    jq --argjson actions "$ANON_ACTIONS" \
       '.identities += [{
         "name": "anonymous",
         "actions": $actions
       }]' "$TMP" > "${TMP}.new"
    mv "${TMP}.new" "$TMP"
fi

jq '.' "$TMP" > "$CONFIG_FILE"
rm -f "$TMP"
chown "${SEAWEEDFS_UID:-1000}:${SEAWEEDFS_GID:-1000}" "$CONFIG_FILE" 2>/dev/null || true
chmod 640 "$CONFIG_FILE"

if [ -n "$PRINTED" ]; then
    echo "$PRINTED"
    echo ""
fi

echo "==========================================="
echo "  identities.json escrito en: $CONFIG_FILE"
echo "  Buckets:        $ALL_BUCKETS"
echo "  Publicos (anon Read): $PUBLIC_BUCKETS"
echo "  Reinicia SeaweedFS para aplicar: 'make restart'"
echo "==========================================="
