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
ACERVO_ADMIN_ACCESS_KEY="${ACERVO_ADMIN_ACCESS_KEY:?ACERVO_ADMIN_ACCESS_KEY is required}"
ACERVO_ADMIN_SECRET_KEY="${ACERVO_ADMIN_SECRET_KEY:?ACERVO_ADMIN_SECRET_KEY is required}"

MC_IMAGE="${MC_IMAGE:-pgsty/mc:RELEASE.2026-04-17T00-00-00Z}"

DATE="${1:-}"
TARGET_BUCKET="${2:-}"

LOCAL_RESTORE_DIR="${PROJECT_DIR}/restore"
SEARCH_DIRS=("${BACKUP_DIR}/monthly" "$LOCAL_RESTORE_DIR")

find_backups() {
    local all=()
    for dir in "${SEARCH_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            while IFS= read -r f; do
                [ -n "$f" ] && all+=("$f")
            done < <(ls -1 "$dir"/backup-*.tar.gz 2>/dev/null | sort -r)
        fi
    done
    echo "${all[@]}"
}

if [ -z "$DATE" ]; then
    echo "Buscando respaldos en:"
    for dir in "${SEARCH_DIRS[@]}"; do
        echo "  - $dir"
    done

    BACKUPS=($(find_backups))

    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo "No se encontraron respaldos."
        exit 1
    fi

    if [ ${#BACKUPS[@]} -eq 1 ]; then
        SELECTED_FILE="${BACKUPS[0]}"
        DATE=$(basename "$SELECTED_FILE" | sed -E 's/backup-(.*)\.tar\.gz/\1/')
        ARCHIVE="$SELECTED_FILE"
        echo ""
        echo "Único respaldo encontrado: $DATE ($(dirname "$SELECTED_FILE"))"
    else
        echo ""
        echo "Respaldos disponibles:"
        for i in "${!BACKUPS[@]}"; do
            FILENAME=$(basename "${BACKUPS[$i]}")
            LOCATION=$(dirname "${BACKUPS[$i]}")
            DATE_STR=$(echo "$FILENAME" | sed -E 's/backup-(.*)\.tar\.gz/\1/')
            echo "  [$((i+1))] $DATE_STR  ($LOCATION)"
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
    fi
else
    if [ -f "${BACKUP_DIR}/monthly/backup-${DATE}.tar.gz" ]; then
        ARCHIVE="${BACKUP_DIR}/monthly/backup-${DATE}.tar.gz"
    elif [ -f "${LOCAL_RESTORE_DIR}/backup-${DATE}.tar.gz" ]; then
        ARCHIVE="${LOCAL_RESTORE_DIR}/backup-${DATE}.tar.gz"
    else
        echo "ERROR: No se encontró respaldo para la fecha ${DATE}"
        echo ""
        echo "Respaldos disponibles:"
        BACKUPS=($(find_backups))
        if [ ${#BACKUPS[@]} -gt 0 ]; then
            for f in "${BACKUPS[@]}"; do
                echo "  $(basename "$f")  ($(dirname "$f"))"
            done
        else
            echo "  (ninguno)"
        fi
        exit 1
    fi
fi

RESTORE_DIR=$(mktemp -d)
trap 'rm -rf "$RESTORE_DIR"' EXIT

echo "Extracting backup from ${ARCHIVE}..."
tar -xzf "$ARCHIVE" -C "$RESTORE_DIR"

if [ -n "$TARGET_BUCKET" ]; then
    BUCKETS="$TARGET_BUCKET"
else
    BUCKETS="${ACERVO_BUCKETS:?ACERVO_BUCKETS is required}"
fi

CONTAINER="acervo-seaweedfs"
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "ERROR: contenedor '$CONTAINER' no esta en ejecucion."
    exit 1
fi

NETWORK=$(docker inspect "$CONTAINER" -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -n 1)

for BUCKET in $BUCKETS; do
    if [ ! -d "${RESTORE_DIR}/${BUCKET}" ]; then
        echo "WARNING: Bucket $BUCKET not found in backup, skipping"
        continue
    fi

    echo "Restoring bucket: $BUCKET (target: $CONTAINER)"
    docker run --rm \
        --network "${NETWORK}" \
        -v "${RESTORE_DIR}:/restore:ro" \
        --entrypoint=/bin/sh \
        "$MC_IMAGE" -c "
            mc alias set acervo http://${CONTAINER}:8333 '${ACERVO_ADMIN_ACCESS_KEY}' '${ACERVO_ADMIN_SECRET_KEY}' && \
            mc mb acervo/${BUCKET} --ignore-existing && \
            mc mirror /restore/${BUCKET} acervo/${BUCKET} --overwrite
        "
    echo "Bucket $BUCKET restored"
done

echo "Restore complete"
