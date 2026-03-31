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

DATE="${1:-}"
TARGET_BUCKET="${2:-}"

# Si no se pasó fecha, mostrar lista interactiva
if [ -z "$DATE" ]; then
    echo "Buscando respaldos disponibles en ${BACKUP_DIR}/monthly..."
    
    # Obtener lista de respaldos ordenados por fecha desc
    BACKUPS=($(ls -1 ${BACKUP_DIR}/monthly/backup-*.tar.gz 2>/dev/null | sort -r || true))
    
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo "No se encontraron respaldos en ${BACKUP_DIR}/monthly."
        exit 1
    fi

    echo ""
    echo "Respaldos disponibles:"
    for i in "${!BACKUPS[@]}"; do
        FILENAME=$(basename "${BACKUPS[$i]}")
        DATE_STR=$(echo "$FILENAME" | sed -E 's/backup-(.*)\.tar\.gz/\1/')
        echo "  [$((i+1))] $DATE_STR"
    done
    echo ""
    
    read -p "Elige el número del respaldo a restaurar (1-${#BACKUPS[@]}): " SELECTION
    
    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "${#BACKUPS[@]}" ]; then
        echo "Selección inválida."
        exit 1
    fi
    
    SELECTED_FILE="${BACKUPS[$((SELECTION-1))]}"
    DATE=$(basename "$SELECTED_FILE" | sed -E 's/backup-(.*)\.tar\.gz/\1/')
    ARCHIVE="$SELECTED_FILE"
else
    ARCHIVE="${BACKUP_DIR}/monthly/backup-${DATE}.tar.gz"
fi

if [ ! -f "$ARCHIVE" ]; then
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
    MINIO_NETWORK=$(docker inspect acervo-minio -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -n 1)

    echo "Restoring bucket: $BUCKET"
    docker run --rm \
        --network "${MINIO_NETWORK}" \
        -v "${RESTORE_DIR}:/restore:ro" \
        --entrypoint=/bin/sh \
        minio/mc -c "
            mc alias set acervo http://acervo-minio:9000 '${MINIO_ACCESS_KEY}' '${MINIO_SECRET_KEY}' && \
            mc mb acervo/${BUCKET} --ignore-existing && \
            mc mirror /restore/${BUCKET} acervo/${BUCKET} --overwrite
        "
    echo "Bucket $BUCKET restored"
done

echo "Restore complete"
