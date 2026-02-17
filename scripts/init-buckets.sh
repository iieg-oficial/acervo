#!/bin/sh
set -e

MINIO_HOST="https://acervo-minio:9000"
ALIAS="acervo"
BUCKETS="mapalab dateengine portal"

echo "Waiting for MinIO to be ready..."
until mc alias set "$ALIAS" "$MINIO_HOST" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" --insecure 2>/dev/null; do
    echo "MinIO not ready, retrying in 3s..."
    sleep 3
done
echo "MinIO connection established"

for BUCKET in $BUCKETS; do
    echo "Creating bucket: $BUCKET"
    mc mb "${ALIAS}/${BUCKET}" --ignore-existing --insecure

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
        mc admin policy create "$ALIAS" "$POLICY_NAME" "$POLICY_FILE" --insecure

    USER="${BUCKET}-user"
    PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

    if mc admin user info "$ALIAS" "$USER" --insecure >/dev/null 2>&1; then
        echo "User $USER already exists, skipping creation"
    else
        echo "Creating user: $USER"
        mc admin user add "$ALIAS" "$USER" "$PASS" --insecure
        mc admin policy attach "$ALIAS" "$POLICY_NAME" --user "$USER" --insecure
        echo "=========================================="
        echo "  Bucket:   $BUCKET"
        echo "  User:     $USER"
        echo "  Password: $PASS"
        echo "=========================================="
    fi
done

echo "Bucket initialization complete"
