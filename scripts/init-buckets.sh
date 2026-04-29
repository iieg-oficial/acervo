#!/bin/sh
set -e

MINIO_HOST="${MINIO_INIT_ENDPOINT:-http://acervo-minio:9000}"
ALIAS="acervo"
ALL_BUCKETS="${MINIO_BUCKETS:?MINIO_BUCKETS is required}"
PUBLIC_BUCKETS="${ACERVO_PUBLIC_BUCKETS:-portal mapalab mariachi}"

ROTATE=0
TARGET=""

while [ $# -gt 0 ]; do
    case "$1" in
        --rotate)
            ROTATE=1
            shift
            ;;
        -h|--help)
            cat <<HELP
Uso: $0 [--rotate] [BUCKET]

  Sin argumentos:    Inicializa todos los buckets de MINIO_BUCKETS. Si un user
                     ya existe, no toca su password (la del primer arranque
                     persiste).
  BUCKET:            Inicializa solo ese bucket.
  --rotate:          Si el user del bucket ya existe, sobreescribe su password
                     con una nueva aleatoria de 32 chars y la imprime.
                     Combinable con BUCKET para rotar uno solo.

Ejemplos:
  $0                          # init de todos
  $0 mariachi                 # init solo del bucket mariachi
  $0 --rotate                 # rota password de TODOS los users
  $0 --rotate portal          # rota password solo del user portal-user
HELP
            exit 0
            ;;
        --*)
            echo "ERROR: flag desconocido: $1" >&2
            exit 1
            ;;
        *)
            if [ -n "$TARGET" ]; then
                echo "ERROR: solo se admite un bucket como argumento posicional" >&2
                exit 1
            fi
            TARGET="$1"
            shift
            ;;
    esac
done

if [ -n "$TARGET" ]; then
    VALID=false
    for b in $ALL_BUCKETS; do
        [ "$b" = "$TARGET" ] && VALID=true
    done
    if [ "$VALID" = false ]; then
        echo "ERROR: Bucket '$TARGET' no esta en MINIO_BUCKETS. Opciones: $ALL_BUCKETS"
        exit 1
    fi
    BUCKETS="$TARGET"
else
    BUCKETS="$ALL_BUCKETS"
fi

echo "Waiting for MinIO to be ready..."
until mc alias set "$ALIAS" "$MINIO_HOST" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" --insecure 2>/dev/null; do
    echo "MinIO not ready, retrying in 3s..."
    sleep 3
done
echo "MinIO connection established"

if mc ls "${ALIAS}/dateengine" >/dev/null 2>&1; then
    echo "Detected legacy bucket 'dateengine' (typo). Migrating to 'dataengine'..."
    mc mb "${ALIAS}/dataengine" --ignore-existing
    mc mirror --remove "${ALIAS}/dateengine/" "${ALIAS}/dataengine/" 2>&1 | tail -3 || true
    mc rb "${ALIAS}/dateengine" --force 2>/dev/null || true
    mc admin user remove "$ALIAS" "dateengine-user" 2>/dev/null || true
    echo "Migration complete: dateengine -> dataengine"
fi

for BUCKET in $BUCKETS; do
    echo "Processing bucket: $BUCKET"
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
    mc admin policy create "$ALIAS" "$POLICY_NAME" "$POLICY_FILE" --insecure 2>/dev/null \
        || mc admin policy create "$ALIAS" "$POLICY_NAME" "$POLICY_FILE" 2>/dev/null \
        || true

    USER="${BUCKET}-user"
    USER_EXISTS=0
    if mc admin user info "$ALIAS" "$USER" >/dev/null 2>&1; then
        USER_EXISTS=1
    fi

    if [ "$USER_EXISTS" = "1" ] && [ "$ROTATE" != "1" ]; then
        echo "User $USER ya existe (usa --rotate para generar password nueva)."
    else
        PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
        if [ "$USER_EXISTS" = "1" ]; then
            echo "Rotating password for user: $USER"
        else
            echo "Creating user: $USER"
        fi
        mc admin user add "$ALIAS" "$USER" "$PASS"
        mc admin policy attach "$ALIAS" "$POLICY_NAME" --user "$USER" 2>/dev/null || true
        echo "=========================================="
        echo "  Bucket:   $BUCKET"
        echo "  User:     $USER"
        echo "  Password: $PASS"
        echo "=========================================="
    fi

    IS_PUBLIC=0
    for pb in $PUBLIC_BUCKETS; do
        [ "$pb" = "$BUCKET" ] && IS_PUBLIC=1
    done
    if [ "$IS_PUBLIC" = "1" ]; then
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
        echo "Anonymous GetObject policy applied to $BUCKET"
    fi
done

echo "Bucket initialization complete"
