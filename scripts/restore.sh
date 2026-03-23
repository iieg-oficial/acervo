#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

ENV_FILE="${ENV_FILE:-.env}"
if [ -f "$PROJECT_DIR/$ENV_FILE" ]; then
    set -a
    . "$PROJECT_DIR/$ENV_FILE"
    set +a
fi

BACKUP_DIR="${BACKUP_DIR:-/backups/acervo}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:?MINIO_ACCESS_KEY is required}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:?MINIO_SECRET_KEY is required}"

usage() {
    echo "Usage: $0 <DATE> [BUCKET]"
    echo ""
    echo "  DATE    Backup date (YYYY-MM-DD)"
    echo "  BUCKET  Optional: specific bucket to restore (mapalab, dateengine, portal)"
    echo ""
    echo "Examples:"
    echo "  $0 2026-01-15              # Restore all buckets from Jan 15"
    echo "  $0 2026-01-15 mapalab      # Restore only mapalab bucket"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

DATE="$1"
TARGET_BUCKET="${2:-}"

ARCHIVE=""
if [ -f "${BACKUP_DIR}/monthly/backup-${DATE}.tar.gz" ]; then
    ARCHIVE="${BACKUP_DIR}/monthly/backup-${DATE}.tar.gz"
fi

if [ -z "$ARCHIVE" ]; then
    echo "ERROR: No backup found for date ${DATE}"
    echo "Available backups:"
    find "$BACKUP_DIR" -name "backup-*.tar.gz" -printf "  %f (%h)\n" 2>/dev/null | sort
    exit 1
fi

RESTORE_DIR=$(mktemp -d)
trap 'rm -rf "$RESTORE_DIR"' EXIT

echo "Extracting backup from ${ARCHIVE}..."
tar -xzf "$ARCHIVE" -C "$RESTORE_DIR"

if [ -n "$TARGET_BUCKET" ]; then
    BUCKETS="$TARGET_BUCKET"
else
    BUCKETS="mapalab dateengine portal"
fi

for BUCKET in $BUCKETS; do
    if [ ! -d "${RESTORE_DIR}/${BUCKET}" ]; then
        echo "WARNING: Bucket $BUCKET not found in backup, skipping"
        continue
    fi

    # Determinar dinámicamente la red del contenedor acervo-minio
    MINIO_NETWORK=$(docker inspect acervo-minio -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' | head -n 1)

    echo "Restoring bucket: $BUCKET"
    docker run --rm \
        --network "${MINIO_NETWORK}" \
        -v "${RESTORE_DIR}:/restore:ro" \
        minio/mc sh -c "
            mc alias set acervo http://acervo-minio:9000 '${MINIO_ACCESS_KEY}' '${MINIO_SECRET_KEY}' && \
            mc mb acervo/${BUCKET} --ignore-existing && \
            mc mirror /restore/${BUCKET} acervo/${BUCKET} --overwrite
        "
    echo "Bucket $BUCKET restored"
done

echo "Restore complete"
