#!/bin/bash
# =============================================================================
# scripts/migrate.sh
#
# Orquestador one-button para la migracion MinIO -> SeaweedFS.
# Detecta el entorno y se comporta:
#   - GCP (todos los repos colocados en /IIEG/*): automatico. Actualiza los
#     .env de los consumidores y reinicia.
#   - Administracion (VMs separadas, solo acervo aqui): semi-automatico.
#     Hace lo que puede en este host e imprime las instrucciones exactas
#     para los otros VMs.
#
# Override manual: MIGRATE_MODE=gcp|admin
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

ENV_FILE="${ENV_FILE:-.env}"
CONFIG_FILE="$PROJECT_DIR/config/identities.json"

GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

step()  { echo ""; echo "${BOLD}${GREEN}==> $1${RESET}"; }
info()  { echo "${YELLOW}    $1${RESET}"; }
warn()  { echo "${YELLOW}[!] $1${RESET}"; }
err()   { echo "${RED}[ERROR] $1${RESET}" >&2; }
ok()    { echo "${GREEN}[OK] $1${RESET}"; }

CONSUMER_REPOS=(
    "/home/egar/IIEG/mariachi"
    "/home/egar/IIEG/huachicol"
    "/home/egar/IIEG/mapalab-dataengine"
)

detect_mode() {
    if [ -n "${MIGRATE_MODE:-}" ]; then
        echo "$MIGRATE_MODE"
        return
    fi
    local found=0
    for r in "${CONSUMER_REPOS[@]}"; do
        [ -d "$r" ] && found=$((found+1))
    done
    if [ "$found" -ge 2 ]; then
        echo "gcp"
    else
        echo "admin"
    fi
}

# -----------------------------------------------------------------------------
# Fase 0: pre-flight
# -----------------------------------------------------------------------------
step "Fase 0 — Pre-flight"

MODE=$(detect_mode)
info "Modo detectado: $MODE"
info "Override: export MIGRATE_MODE=gcp|admin"

if [ ! -f "$ENV_FILE" ]; then
    err "No existe $ENV_FILE. Corre 'make setup' primero."
    exit 1
fi
set -a; . "$ENV_FILE"; set +a

require_var() {
    eval "val=\${$1:-}"
    if [ -z "$val" ]; then
        err "Variable $1 no esta definida en $ENV_FILE."
        exit 1
    fi
}
require_var ACERVO_ADMIN_ACCESS_KEY
require_var ACERVO_ADMIN_SECRET_KEY
require_var ACERVO_BUCKETS
ok "$ENV_FILE valido"

MINIO_VOLUME_DEFAULT="${MIGRATE_MINIO_VOLUME:-acervo_minio_data}"
HAS_MINIO_DATA=0
if docker volume inspect "$MINIO_VOLUME_DEFAULT" >/dev/null 2>&1; then
    HAS_MINIO_DATA=1
    ok "Volumen MinIO '$MINIO_VOLUME_DEFAULT' encontrado (se migrara su contenido)"
else
    warn "Volumen '$MINIO_VOLUME_DEFAULT' no existe — la fase de mirror se SALTARA (instalacion limpia)"
fi

# -----------------------------------------------------------------------------
# Fase 1: snapshot de seguridad
# -----------------------------------------------------------------------------
step "Fase 1 — Snapshot de seguridad"

if [ "$HAS_MINIO_DATA" = "1" ] && docker ps --format '{{.Names}}' | grep -qx acervo-minio; then
    info "MinIO esta corriendo. Disparando backup..."
    if ENV_FILE="$ENV_FILE" bash "$SCRIPT_DIR/backup.sh"; then
        ok "Snapshot tar.gz creado"
    else
        err "El backup fallo. Aborta y revisa logs antes de continuar."
        exit 1
    fi
elif [ "$HAS_MINIO_DATA" = "1" ]; then
    info "Volumen existe pero el contenedor acervo-minio no esta corriendo."
    info "El mirror leera el volumen directamente. Si quieres un tar.gz adicional, levanta MinIO primero."
else
    info "Nada que respaldar (no hay MinIO previo)."
fi

# -----------------------------------------------------------------------------
# Fase 2: generar identities + arrancar SeaweedFS
# -----------------------------------------------------------------------------
step "Fase 2 — Generar identities.json y arrancar SeaweedFS"

if [ -s "$CONFIG_FILE" ]; then
    warn "$CONFIG_FILE ya existe. Se preservaran las passwords existentes."
    info "Para forzar rotacion: 'make rotate-seaweedfs' (rota TODOS) o 'make rotate-seaweedfs BUCKET=...'"
fi

docker compose --env-file "$ENV_FILE" -f docker-compose.yml --profile init run --rm acervo-init
ok "identities.json generado/actualizado"

docker compose --env-file "$ENV_FILE" -f docker-compose.yml up -d
info "Esperando healthcheck (max ~2 min)..."
TRIES=0
until [ "$(docker inspect -f '{{.State.Health.Status}}' acervo-seaweedfs 2>/dev/null || echo missing)" = "healthy" ]; do
    TRIES=$((TRIES+1))
    if [ "$TRIES" -gt 40 ]; then
        err "SeaweedFS no se volvio healthy. Revisa: docker logs acervo-seaweedfs"
        exit 1
    fi
    sleep 3
done
ok "SeaweedFS healthy"

# -----------------------------------------------------------------------------
# Fase 3: mirror MinIO -> SeaweedFS
# -----------------------------------------------------------------------------
if [ "$HAS_MINIO_DATA" = "1" ]; then
    step "Fase 3 — Mirror MinIO -> SeaweedFS"
    if [ -z "${MIGRATE_MINIO_ACCESS_KEY:-}" ] || [ -z "${MIGRATE_MINIO_SECRET_KEY:-}" ]; then
        err "MIGRATE_MINIO_ACCESS_KEY/SECRET_KEY requeridas en $ENV_FILE para la fase de mirror."
        info "Agregalas (root del MinIO viejo) y vuelve a correr 'make migrate'."
        exit 1
    fi
    ENV_FILE="$ENV_FILE" bash "$SCRIPT_DIR/migrate-from-minio.sh"
    ok "Mirror completo"
else
    step "Fase 3 — Mirror MinIO -> SeaweedFS (SALTADA)"
    info "No habia volumen MinIO. SeaweedFS arranca con buckets vacios."
fi

# -----------------------------------------------------------------------------
# Fase 4: extraer secrets para propagacion
# -----------------------------------------------------------------------------
step "Fase 4 — Extraer secrets de identities.json"

declare -A SECRETS
for bucket in $ACERVO_BUCKETS; do
    SECRETS[$bucket]=$(jq -r ".identities[] | select(.name == \"${bucket}-user\") | .credentials[0].secretKey // \"\"" "$CONFIG_FILE")
    if [ -z "${SECRETS[$bucket]}" ]; then
        err "No se encontro secret para ${bucket}-user en $CONFIG_FILE"
        exit 1
    fi
done
ok "Secrets extraidos para ${#SECRETS[@]} buckets"

# -----------------------------------------------------------------------------
# Fase 5: propagacion (GCP) o instrucciones (admin)
# -----------------------------------------------------------------------------
step "Fase 5 — Propagacion a consumidores"

print_creds() {
    echo ""
    echo "  ${BOLD}Credenciales nuevas:${RESET}"
    for bucket in $ACERVO_BUCKETS; do
        echo "    ACERVO_${bucket^^}_ACCESS_KEY=${bucket}-user"
        echo "    ACERVO_${bucket^^}_SECRET_KEY=${SECRETS[$bucket]}"
    done
    echo "    ACERVO_ENDPOINT=acervo-seaweedfs:8333"
    echo "    ACERVO_PUBLIC_ENDPOINT=/acervo"
    echo ""
}

update_mariachi() {
    local env_file="$1"
    [ ! -f "$env_file" ] && return
    info "Actualizando $env_file..."
    # Endpoint
    sed -i -E \
        -e 's|^ACERVO_HOST_IP=.*|ACERVO_HOST_IP=acervo-seaweedfs|' \
        -e 's|^ACERVO_ENDPOINT=.*|ACERVO_ENDPOINT=acervo-seaweedfs:8333|' \
        "$env_file"
    # Por cada bucket, sustituir el SECRET_KEY
    for bucket in portal mapalab mariachi sieej iieg; do
        if [ -n "${SECRETS[$bucket]:-}" ]; then
            local var="ACERVO_${bucket^^}_SECRET_KEY"
            sed -i -E "s|^${var}=.*|${var}=${SECRETS[$bucket]}|" "$env_file"
        fi
    done
    ok "$(basename "$env_file") actualizado"
}

update_huachicol() {
    local env_file="/home/egar/IIEG/huachicol/.env"
    [ ! -f "$env_file" ] && return
    info "Actualizando $env_file (metricas SeaweedFS sin auth)..."
    sed -i -E \
        -e 's|^ACERVO_MINIO_TARGET=.*|ACERVO_METRICS_TARGET=acervo-seaweedfs:9091|' \
        -e '/^ACERVO_MINIO_TOKEN=/d' \
        -e '/^MINIO_ENDPOINT=/d' \
        -e '/^MINIO_BUCKET_USER=/d' \
        -e '/^MINIO_BUCKET_PASSWORD=/d' \
        "$env_file"
    ok "huachicol/.env actualizado"
}

update_dataengine() {
    local env_file="/home/egar/IIEG/mapalab-dataengine/.env"
    [ ! -f "$env_file" ] && return
    info "Actualizando $env_file..."
    sed -i -E \
        -e 's|^AO_ENDPOINT=.*|AO_ENDPOINT=http://acervo-seaweedfs:8333|' \
        -e 's|^AO_BUCKET=.*|AO_BUCKET=dataengine|' \
        -e 's|^AO_ACCESS_KEY=.*|AO_ACCESS_KEY=dataengine-user|' \
        -e "s|^AO_SECRET_KEY=.*|AO_SECRET_KEY=${SECRETS[dataengine]}|" \
        "$env_file"
    ok "mapalab-dataengine/.env actualizado"
}

if [ "$MODE" = "gcp" ]; then
    info "Modo GCP: actualizando .env de consumidores in-place..."
    for f in /home/egar/IIEG/mariachi/.env.production /home/egar/IIEG/mariachi/.env.staging /home/egar/IIEG/mariachi/.env.development; do
        update_mariachi "$f"
    done
    update_huachicol
    update_dataengine

    print_creds

    step "Fase 6 — Reiniciar consumidores"
    info "Ejecuta (manual, requiere docker compose en cada repo):"
    cat <<EOF

  cd /home/egar/IIEG/gateway-hub && \\
    sed -i 's|ACERVO_HOST=acervo-minio:9000|ACERVO_HOST=acervo-seaweedfs:8333|' .env.production && \\
    docker compose up -d nginx

  cd /home/egar/IIEG/mariachi && docker compose up -d --force-recreate
  cd /home/egar/IIEG/huachicol && docker compose up -d --force-recreate prometheus
  cd /home/egar/IIEG/mapalab-dataengine && docker compose up -d --force-recreate

  curl -I https://iieg.jalisco.gob.mx/acervo/iieg/v1/logo.svg   # smoke test
EOF
else
    cat <<EOF

  ${BOLD}${YELLOW}Modo ADMINISTRACION (semi-automatico).${RESET}
  Acervo y gateway-hub viven en S1; los consumidores en otros servidores.
  Sigue los pasos del runbook desde la VM correspondiente:

  ${BOLD}docs/migracion-runbook.md${RESET}

EOF
    print_creds
    info "Copia las creds de arriba y aplicalas segun el runbook."
fi

# -----------------------------------------------------------------------------
step "Migracion completa"
echo ""
echo "  ${BOLD}Estado actual:${RESET}"
echo "    - SeaweedFS healthy en acervo-seaweedfs:8333"
echo "    - config/identities.json escrito"
[ "$HAS_MINIO_DATA" = "1" ] && echo "    - Datos migrados de MinIO"
[ "$MODE" = "gcp" ] && echo "    - .env de consumidores actualizados"
echo ""
echo "  ${BOLD}Que NO se hizo automaticamente:${RESET}"
echo "    - Apagar MinIO viejo (lo dejas hasta confirmar smoke tests)"
echo "    - Reiniciar el gateway-hub (ver comandos arriba)"
echo "    - Reiniciar consumidores (ver comandos arriba)"
echo ""
