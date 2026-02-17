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
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
BACKUP_RETENTION_WEEKS="${BACKUP_RETENTION_WEEKS:-4}"
BACKUP_RETENTION_MONTHS="${BACKUP_RETENTION_MONTHS:-3}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:?MINIO_ACCESS_KEY is required}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:?MINIO_SECRET_KEY is required}"

DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOG_DIR="${BACKUP_DIR}/logs"
LOG_FILE="${LOG_DIR}/backup-${TIMESTAMP}.log"
DAILY_DIR="${BACKUP_DIR}/daily/${DATE}"

mkdir -p "$LOG_DIR" "$DAILY_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting backup"

BUCKETS="mapalab dateengine portal"

for BUCKET in $BUCKETS; do
    log "Backing up bucket: $BUCKET"
    BUCKET_DIR="${DAILY_DIR}/${BUCKET}"
    mkdir -p "$BUCKET_DIR"

    docker run --rm \
        --network acervo_acervo_internal \
        -v "${DAILY_DIR}:/backup" \
        -v "${PROJECT_DIR}/nginx/ssl/acervo.crt:/etc/ssl/certs/acervo.crt:ro" \
        minio/mc sh -c "
            mc alias set acervo https://acervo-minio:9000 '${MINIO_ACCESS_KEY}' '${MINIO_SECRET_KEY}' --insecure && \
            mc mirror acervo/${BUCKET} /backup/${BUCKET} --insecure
        " 2>&1 | tee -a "$LOG_FILE"

    log "Bucket $BUCKET backup complete"
done

ARCHIVE="${BACKUP_DIR}/daily/backup-${DATE}.tar.gz"
log "Compressing backup to ${ARCHIVE}"
tar -czf "$ARCHIVE" -C "${DAILY_DIR}" .
rm -rf "$DAILY_DIR"
log "Compression complete"

DAY_OF_WEEK=$(date +%u)
if [ "$DAY_OF_WEEK" -eq 7 ]; then
    mkdir -p "${BACKUP_DIR}/weekly"
    cp "$ARCHIVE" "${BACKUP_DIR}/weekly/backup-${DATE}.tar.gz"
    log "Weekly backup saved"
fi

DAY_OF_MONTH=$(date +%d)
if [ "$DAY_OF_MONTH" -eq 1 ]; then
    mkdir -p "${BACKUP_DIR}/monthly"
    cp "$ARCHIVE" "${BACKUP_DIR}/monthly/backup-${DATE}.tar.gz"
    log "Monthly backup saved"
fi

log "Rotating old backups"
find "${BACKUP_DIR}/daily" -name "backup-*.tar.gz" -mtime +"$BACKUP_RETENTION_DAYS" -delete 2>/dev/null || true
WEEKS_IN_DAYS=$((BACKUP_RETENTION_WEEKS * 7))
find "${BACKUP_DIR}/weekly" -name "backup-*.tar.gz" -mtime +"$WEEKS_IN_DAYS" -delete 2>/dev/null || true
MONTHS_IN_DAYS=$((BACKUP_RETENTION_MONTHS * 30))
find "${BACKUP_DIR}/monthly" -name "backup-*.tar.gz" -mtime +"$MONTHS_IN_DAYS" -delete 2>/dev/null || true
find "${LOG_DIR}" -name "backup-*.log" -mtime +30 -delete 2>/dev/null || true

log "Backup complete"
