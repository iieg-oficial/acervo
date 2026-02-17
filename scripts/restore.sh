#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    . "$PROJECT_DIR/.env"
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
for DIR in daily weekly monthly; do
    if [ -f "${BACKUP_DIR}/${DIR}/backup-${DATE}.tar.gz" ]; then
        ARCHIVE="${BACKUP_DIR}/${DIR}/backup-${DATE}.tar.gz"
        break
    fi
done

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

    echo "Restoring bucket: $BUCKET"
    docker run --rm \
        --network acervo_acervo_internal \
        -v "${RESTORE_DIR}:/restore:ro" \
        -v "${PROJECT_DIR}/nginx/ssl/acervo.crt:/etc/ssl/certs/acervo.crt:ro" \
        minio/mc sh -c "
            mc alias set acervo https://acervo-minio:9000 '${MINIO_ACCESS_KEY}' '${MINIO_SECRET_KEY}' --insecure && \
            mc mb acervo/${BUCKET} --ignore-existing --insecure && \
            mc mirror /restore/${BUCKET} acervo/${BUCKET} --overwrite --insecure
        "
    echo "Bucket $BUCKET restored"
done

echo "Restore complete"
