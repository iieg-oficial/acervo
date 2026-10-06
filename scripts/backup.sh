#!/bin/bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

ENV_FILE="${ENV_FILE:-.env}"
if [ ! -f "$PROJECT_DIR/$ENV_FILE" ]; then
    echo "ERROR: archivo $ENV_FILE no encontrado en $PROJECT_DIR." >&2
    echo "       Corre 'make setup' para crearlo desde .env.example y editalo con creds reales." >&2
    exit 1
fi
set -a
. "$PROJECT_DIR/$ENV_FILE"
set +a

require_var() {
    eval "val=\${$1:-}"
    if [ -z "$val" ]; then
        echo "ERROR: variable $1 no esta definida en $ENV_FILE." >&2
        exit 1
    fi
}

require_var ACERVO_ADMIN_ACCESS_KEY
require_var ACERVO_ADMIN_SECRET_KEY
require_var ACERVO_BUCKETS

BACKUP_DIR="${BACKUP_DIR:-/backups/acervo}"
BACKUP_RETENTION_MONTHS="${BACKUP_RETENTION_MONTHS:-2}"
BUCKETS="$ACERVO_BUCKETS"

SEAWEEDFS_CONTAINER="${SEAWEEDFS_CONTAINER:-acervo-seaweedfs}"
MC_IMAGE="${MC_IMAGE:-pgsty/mc:RELEASE.2026-04-17T00-00-00Z}"

DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOG_DIR="${BACKUP_DIR}/logs"
LOG_FILE="${LOG_DIR}/backup-${TIMESTAMP}.log"
MONTHLY_DIR="${BACKUP_DIR}/monthly/${DATE}"

mkdir -p "$LOG_DIR" "$MONTHLY_DIR"
chmod 700 "$BACKUP_DIR" "${BACKUP_DIR}/monthly" "$LOG_DIR" 2>/dev/null || true

source "$SCRIPT_DIR/mc-host.sh"
export_mc_host "$SEAWEEDFS_CONTAINER"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting backup"

NETWORK=$(docker inspect "$SEAWEEDFS_CONTAINER" -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -n 1)

for BUCKET in $BUCKETS; do
    log "Backing up bucket: $BUCKET"
    BUCKET_DIR="${MONTHLY_DIR}/${BUCKET}"
    mkdir -p "$BUCKET_DIR"

    docker run --rm \
        --network "${NETWORK}" \
        -e MC_HOST_acervo \
        -v "${MONTHLY_DIR}:/backup" \
        "$MC_IMAGE" mirror "acervo/${BUCKET}" "/backup/${BUCKET}" 2>&1 | tee -a "$LOG_FILE"

    log "Bucket $BUCKET backup complete"
done

ARCHIVE="${BACKUP_DIR}/monthly/backup-${DATE}.tar.gz"
log "Compressing backup to ${ARCHIVE}"
tar -czf "$ARCHIVE" -C "${MONTHLY_DIR}" .
docker run --rm -v "${MONTHLY_DIR}:/cleanup" alpine find /cleanup -mindepth 1 -delete
rmdir "$MONTHLY_DIR" 2>/dev/null || true
log "Compression complete"

log "Rotating old backups"
MONTHS_IN_DAYS=$((BACKUP_RETENTION_MONTHS * 30))
find "${BACKUP_DIR}/monthly" -name "backup-*.tar.gz" -mtime +"$MONTHS_IN_DAYS" -delete 2>/dev/null || true
find "${LOG_DIR}" -name "backup-*.log" -mtime +90 -delete 2>/dev/null || true

log "Backup complete"
