#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

source make/lib.sh
source make/repo.sh

ENV_FILE="${ENV_FILE:-.env}"
if [ ! -f "$ENV_FILE" ]; then
    fail "Env:archivo $ENV_FILE no encontrado en $PROJECT_DIR" \
         "Corre 'make setup' para crearlo desde .env.example y editalo con creds reales."
fi
set -a
. "$ENV_FILE"
set +a

require_var() {
    local val
    eval "val=\${$1:-}"
    if [ -z "$val" ]; then
        fail "Env:variable $1 no esta definida en $ENV_FILE" \
             'Definela y vuelve a intentar.'
    fi
}

require_var ACERVO_ADMIN_ACCESS_KEY
require_var ACERVO_ADMIN_SECRET_KEY
require_var ACERVO_BUCKETS

BACKUP_DIR="${BACKUP_DIR:-/backups/acervo}"
MC_IMAGE="${MC_IMAGE:-pgsty/mc:RELEASE.2026-04-17T00-00-00Z}"
CONTAINER="${SEAWEEDFS_CONTAINER:-acervo-seaweedfs}"
SKIP_BUCKETS="${ACERVO_RESTORE_SKIP-portal}"
STAGING_DIR="${RESTORE_STAGING_DIR:-$PROJECT_DIR}/.restore_staging"

DATE="${1:-}"
TARGET_BUCKET="${2:-}"

human() { numfmt --to=iec --from-unit=1024 "$1"; }

if [ -n "$DATE" ]; then
    if [ -f "${BACKUP_DIR}/monthly/backup-${DATE}.tar.gz" ]; then
        ARCHIVE="${BACKUP_DIR}/monthly/backup-${DATE}.tar.gz"
    elif [ -f "restore/backup-${DATE}.tar.gz" ]; then
        ARCHIVE="restore/backup-${DATE}.tar.gz"
    else
        fail "Backup:no hay respaldo con fecha ${DATE}" \
             'Corre make restore sin argumentos para elegir de la lista.'
    fi
else
    ARCHIVE=$(pick_backup)
fi

if [ -n "$TARGET_BUCKET" ]; then
    SELECCION="$TARGET_BUCKET"
else
    SELECCION=$(pick_bucket)
fi

BUCKETS=''
OMITIDOS=''
if [ "$SELECCION" = 'todos' ]; then
    for bucket in $ACERVO_BUCKETS; do
        if printf '%s\n' $SKIP_BUCKETS | grep -qx "$bucket"; then
            OMITIDOS="${OMITIDOS}${bucket} "
        else
            BUCKETS="${BUCKETS}${bucket} "
        fi
    done
else
    BUCKETS="$SELECCION"
fi
BUCKETS=$(printf '%s' "$BUCKETS" | xargs)
OMITIDOS=$(printf '%s' "$OMITIDOS" | xargs)

if [ -z "$BUCKETS" ]; then
    fail 'Buckets:no queda ninguno por restaurar' \
         "Todos los de ACERVO_BUCKETS estan en ACERVO_RESTORE_SKIP ($SKIP_BUCKETS)."
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    fail "Acervo:el contenedor $CONTAINER no esta en ejecucion" \
         'Levanta el stack con make up antes de restaurar.'
fi
NETWORK=$(docker inspect "$CONTAINER" -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -n 1)

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
trap 'rm -rf "$STAGING_DIR"' EXIT

archive_kb=$(du -k "$ARCHIVE" | cut -f1)
avail_kb=$(df -Pk "$STAGING_DIR" | awk 'NR == 2 { print $4 }')
needed_kb=$((archive_kb * 2))

row 'Archivo' "$(human "$archive_kb")" "$C_GREEN" "$ARCHIVE"
row 'Buckets' "$(printf '%s' "$BUCKETS" | wc -w)" "$C_GREEN" "$BUCKETS"
[ -n "$OMITIDOS" ] && row 'Omitidos' "$(printf '%s' "$OMITIDOS" | wc -w)" "$C_YELLOW" "$OMITIDOS"
row 'Staging' "$(human "$avail_kb") libres" "$C_GREEN" "$STAGING_DIR"

if [ "$avail_kb" -lt "$needed_kb" ]; then
    fail "Espacio:el staging necesita ~$(human "$needed_kb") y solo hay $(human "$avail_kb")" \
         'Libera espacio o mueve el staging a otro disco: RESTORE_STAGING_DIR=/ruta make restore'
fi

confirm "Esto sobrescribe en acervo los objetos de: ${BUCKETS}." 'restaurar'
rule

restore_bucket() {
    docker run --rm \
        --network "$NETWORK" \
        -v "${STAGING_DIR}:/restore:ro" \
        --entrypoint=/bin/sh \
        "$MC_IMAGE" -c "
            mc alias set acervo http://${CONTAINER}:8333 '${ACERVO_ADMIN_ACCESS_KEY}' '${ACERVO_ADMIN_SECRET_KEY}' && \
            mc mb acervo/${1} --ignore-existing && \
            mc mirror /restore/${1} acervo/${1} --overwrite
        "
}

run_step 'Extraer' tar -xzf "$ARCHIVE" -C "$STAGING_DIR"

for bucket in $BUCKETS; do
    if [ ! -d "${STAGING_DIR}/${bucket}" ]; then
        row "$bucket" 'sin datos' "$C_YELLOW" 'no viene en el respaldo'
        continue
    fi
    run_step "$bucket" restore_bucket "$bucket"
done

rule
printf '\n'
