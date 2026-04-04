#!/bin/sh
set -e

MINIO_HOST="${MINIO_SERVER_URL:?MINIO_SERVER_URL is required}"
ALIAS="acervo"
ALL_BUCKETS="${MINIO_BUCKETS:?MINIO_BUCKETS is required}"

# Si se pasa un argumento, solo inicializar ese bucket
if [ -n "${1:-}" ]; then
    VALID=false
    for b in $ALL_BUCKETS; do
        [ "$b" = "$1" ] && VALID=true
    done
    if [ "$VALID" = false ]; then
        echo "ERROR: Bucket '$1' no es valido. Opciones: $ALL_BUCKETS"
        exit 1
    fi
    BUCKETS="$1"
else
    BUCKETS="$ALL_BUCKETS"
fi

echo "Waiting for MinIO to be ready..."
until mc alias set "$ALIAS" "$MINIO_HOST" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" --insecure 2>/dev/null; do
    echo "MinIO not ready, retrying in 3s..."
    sleep 3
done
echo "MinIO connection established"

for BUCKET in $BUCKETS; do
    echo "Creating bucket: $BUCKET"
    mc mb "${ALIAS}/${BUCKET}" --ignore-existing
    POLICY_FILE="/tmp/policy-${BUCKET}.json"
    cat > "$POLICY_FILE" <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:*"],
            "Resource": [
                "arn:aws:s3:::${BUCKET}",
                "arn:aws:s3:::${BUCKET}/*"
            ]
        }
    ]
}
POLICY

    POLICY_NAME="policy-${BUCKET}"
    echo "Creating policy: $POLICY_NAME"
    mc admin policy create "$ALIAS" "$POLICY_NAME" "$POLICY_FILE" --insecure 2>/dev/null || \
        mc admin policy create "$ALIAS" "$POLICY_NAME" "$POLICY_FILE"
    USER="${BUCKET}-user"
    PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

    if mc admin user info "$ALIAS" "$USER" >/dev/null 2>&1; then
        echo "User $USER already exists, skipping creation"
    else
        echo "Creating user: $USER"
        mc admin user add "$ALIAS" "$USER" "$PASS"
        mc admin policy attach "$ALIAS" "$POLICY_NAME" --user "$USER"
        echo "=========================================="
        echo "  Bucket:   $BUCKET"
        echo "  User:     $USER"
        echo "  Password: $PASS"
        echo "=========================================="
    fi

    if [ "$BUCKET" = "portal" ] || [ "$BUCKET" = "mapalab" ]; then
        echo "Setting public GetObject-only policy on bucket: $BUCKET"
        ANON_POLICY_FILE="/tmp/anon-policy-${BUCKET}.json"
        cat > "$ANON_POLICY_FILE" <<ANONPOLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"AWS": ["*"]},
      "Action": ["s3:GetObject"],
      "Resource": ["arn:aws:s3:::${BUCKET}/*"]
    }
  ]
}
ANONPOLICY
        mc anonymous set-json "$ANON_POLICY_FILE" "${ALIAS}/${BUCKET}"
    fi
done

echo "Bucket initialization complete"
