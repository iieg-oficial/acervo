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
BACKUP_RETENTION_MONTHS="${BACKUP_RETENTION_MONTHS:-2}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:?MINIO_ACCESS_KEY is required}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:?MINIO_SECRET_KEY is required}"

DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOG_DIR="${BACKUP_DIR}/logs"
LOG_FILE="${LOG_DIR}/backup-${TIMESTAMP}.log"
MONTHLY_DIR="${BACKUP_DIR}/monthly/${DATE}"

mkdir -p "$LOG_DIR" "$MONTHLY_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting backup"

BUCKETS="mapalab dateengine portal"

for BUCKET in $BUCKETS; do
    log "Backing up bucket: $BUCKET"
    BUCKET_DIR="${MONTHLY_DIR}/${BUCKET}"
    mkdir -p "$BUCKET_DIR"

    # Determinar dinámicamente la red del contenedor acervo-minio
    MINIO_NETWORK=$(docker inspect acervo-minio -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -n 1)
    
    docker run --rm \
        --network "${MINIO_NETWORK}" \
        -v "${MONTHLY_DIR}:/backup" \
        --entrypoint=/bin/sh \
        minio/mc -c "
            mc alias set acervo http://acervo-minio:9000 '${MINIO_ACCESS_KEY}' '${MINIO_SECRET_KEY}' && \
            mc mirror acervo/${BUCKET} /backup/${BUCKET}
        " 2>&1 | tee -a "$LOG_FILE"

    log "Bucket $BUCKET backup complete"
done

ARCHIVE="${BACKUP_DIR}/monthly/backup-${DATE}.tar.gz"
log "Compressing backup to ${ARCHIVE}"
tar -czf "$ARCHIVE" -C "${MONTHLY_DIR}" .
rm -rf "$MONTHLY_DIR"
log "Compression complete"

log "Rotating old backups"
MONTHS_IN_DAYS=$((BACKUP_RETENTION_MONTHS * 30))
find "${BACKUP_DIR}/monthly" -name "backup-*.tar.gz" -mtime +"$MONTHS_IN_DAYS" -delete 2>/dev/null || true
find "${LOG_DIR}" -name "backup-*.log" -mtime +90 -delete 2>/dev/null || true

log "Backup complete"
