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

: "${ACERVO_BUCKETS:?ACERVO_BUCKETS is required}"
: "${MIGRATE_MINIO_ACCESS_KEY:?MIGRATE_MINIO_ACCESS_KEY is required (root key del MinIO viejo)}"
: "${MIGRATE_MINIO_SECRET_KEY:?MIGRATE_MINIO_SECRET_KEY is required}"
: "${ACERVO_ADMIN_ACCESS_KEY:?ACERVO_ADMIN_ACCESS_KEY is required (admin de SeaweedFS nuevo)}"
: "${ACERVO_ADMIN_SECRET_KEY:?ACERVO_ADMIN_SECRET_KEY is required}"

MINIO_VOLUME="${MIGRATE_MINIO_VOLUME:-acervo_minio_data}"
MINIO_IMAGE="${MIGRATE_MINIO_IMAGE:-pgsty/minio:RELEASE.2026-04-17T00-00-00Z}"
MC_IMAGE="${MIGRATE_MC_IMAGE:-pgsty/mc:RELEASE.2026-04-17T00-00-00Z}"
SEAWEEDFS_CONTAINER="${SEAWEEDFS_CONTAINER:-acervo-seaweedfs}"
TMP_MINIO_CONTAINER="acervo-minio-migration"
TMP_NETWORK="acervo-migration-net"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [migrate] $1"
}

cleanup() {
    log "Limpiando contenedor/red temporales..."
    docker stop "$TMP_MINIO_CONTAINER" >/dev/null 2>&1 || true
    docker rm   "$TMP_MINIO_CONTAINER" >/dev/null 2>&1 || true
    docker network rm "$TMP_NETWORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! docker volume inspect "$MINIO_VOLUME" >/dev/null 2>&1; then
    log "ERROR: volumen MinIO '$MINIO_VOLUME' no existe. Nada que migrar."
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$SEAWEEDFS_CONTAINER"; then
    log "ERROR: contenedor '$SEAWEEDFS_CONTAINER' no esta corriendo. Levanta SeaweedFS primero ('make up')."
    exit 1
fi

SEAWEEDFS_NETWORK=$(docker inspect "$SEAWEEDFS_CONTAINER" -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -n 1)
log "SeaweedFS detectado en red: $SEAWEEDFS_NETWORK"

log "Creando red puente temporal..."
docker network create "$TMP_NETWORK" >/dev/null

log "Levantando MinIO efimero contra el volumen '$MINIO_VOLUME'..."
docker run -d \
    --name "$TMP_MINIO_CONTAINER" \
    --network "$TMP_NETWORK" \
    -v "${MINIO_VOLUME}:/data" \
    -e "MINIO_ROOT_USER=${MIGRATE_MINIO_ACCESS_KEY}" \
    -e "MINIO_ROOT_PASSWORD=${MIGRATE_MINIO_SECRET_KEY}" \
    "$MINIO_IMAGE" \
    server /data >/dev/null

log "Conectando MinIO temporal a la red de SeaweedFS..."
docker network connect "$SEAWEEDFS_NETWORK" "$TMP_MINIO_CONTAINER"

log "Esperando a MinIO temporal..."
for i in $(seq 1 30); do
    if docker exec "$TMP_MINIO_CONTAINER" curl -sf http://localhost:9000/minio/health/live >/dev/null 2>&1; then
        log "MinIO listo."
        break
    fi
    sleep 2
done

log "Iniciando mc mirror por bucket..."
FAIL=0
for BUCKET in $ACERVO_BUCKETS; do
    log "Mirror: ${BUCKET}"
    if docker run --rm \
        --network "$SEAWEEDFS_NETWORK" \
        --entrypoint=/bin/sh \
        "$MC_IMAGE" -c "
            mc alias set old http://${TMP_MINIO_CONTAINER}:9000 '${MIGRATE_MINIO_ACCESS_KEY}' '${MIGRATE_MINIO_SECRET_KEY}' >/dev/null && \
            mc alias set new http://${SEAWEEDFS_CONTAINER}:8333 '${ACERVO_ADMIN_ACCESS_KEY}' '${ACERVO_ADMIN_SECRET_KEY}' >/dev/null && \
            mc mb new/${BUCKET} --ignore-existing >/dev/null && \
            mc mirror --overwrite old/${BUCKET} new/${BUCKET}
        "; then
        log "OK: ${BUCKET}"
    else
        log "FAIL: ${BUCKET}"
        FAIL=$((FAIL+1))
    fi
done

if [ "$FAIL" -gt 0 ]; then
    log "ERROR: ${FAIL} bucket(s) fallaron durante el mirror."
    exit 1
fi

log "Verificacion: conteo de objetos por bucket..."
for BUCKET in $ACERVO_BUCKETS; do
    OLD=$(docker run --rm \
        --network "$SEAWEEDFS_NETWORK" \
        --entrypoint=/bin/sh \
        "$MC_IMAGE" -c "
            mc alias set old http://${TMP_MINIO_CONTAINER}:9000 '${MIGRATE_MINIO_ACCESS_KEY}' '${MIGRATE_MINIO_SECRET_KEY}' >/dev/null && \
            mc ls --recursive old/${BUCKET} 2>/dev/null | wc -l
        " | tail -n 1 | tr -d '[:space:]')
    NEW=$(docker run --rm \
        --network "$SEAWEEDFS_NETWORK" \
        --entrypoint=/bin/sh \
        "$MC_IMAGE" -c "
            mc alias set new http://${SEAWEEDFS_CONTAINER}:8333 '${ACERVO_ADMIN_ACCESS_KEY}' '${ACERVO_ADMIN_SECRET_KEY}' >/dev/null && \
            mc ls --recursive new/${BUCKET} 2>/dev/null | wc -l
        " | tail -n 1 | tr -d '[:space:]')
    if [ "$OLD" = "$NEW" ]; then
        log "OK ${BUCKET}: ${OLD} objetos en ambos lados"
    else
        log "DIFF ${BUCKET}: MinIO=${OLD} vs SeaweedFS=${NEW}"
        FAIL=$((FAIL+1))
    fi
done

if [ "$FAIL" -gt 0 ]; then
    log "ERROR: verificacion encontro diferencias. NO apagues MinIO aun."
    exit 1
fi

log "=========================================="
log "Migracion completa. Siguiente paso:"
log "  1. Validar smoke tests contra SeaweedFS (curl, clientes)."
log "  2. Si todo OK: 'docker volume rm $MINIO_VOLUME' (irreversible)."
log "  3. Quitar la referencia a MinIO en gateway-hub y reiniciar consumidores."
log "=========================================="
