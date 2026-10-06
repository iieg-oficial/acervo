CRON_MARKER='# acervo-backup'

init_seaweedfs() {
    dc prod --profile init run --rm "$@" acervo-init
}

pick_bucket() {
    local buckets
    buckets=$(grep -E '^ACERVO_BUCKETS=' .env 2>/dev/null | cut -d= -f2- | tr -d '"')
    if [ -z "$buckets" ]; then
        fail 'Buckets:no hay ACERVO_BUCKETS en .env' \
             'Definela con la lista de buckets antes de rotar.' >&2
    fi
    pick 'Bucket' 'todos' $buckets
}

pick_backup() {
    local base="${BACKUP_DIR:-/backups/acervo}"
    local -a files
    mapfile -t files < <(ls -1t restore/backup-*.tar.gz "$base"/monthly/backup-*.tar.gz 2>/dev/null)
    if [ ${#files[@]} -eq 0 ]; then
        fail "Backup:no hay archivos en restore/ ni en $base/monthly" \
             'Copia un backup-*.tar.gz a restore/ y vuelve a intentar.' >&2
    fi
    pick 'Archivo' "${files[@]}"
}

cron_install() {
    local dir
    dir=$(pwd)
    {
        crontab -l 2>/dev/null | grep -v "$CRON_MARKER" || true
        sed -e "s|/opt/acervo|$dir|g" \
            -e "s|/bin/bash|/usr/bin/env ENV_FILE=.env /bin/bash|g" scripts/backup-cron
    } | crontab -
    row 'Cron' 'instalado' "$C_GREEN" 'mensual, dia 1 a las 3:00'
    crontab -l | grep "$CRON_MARKER" | while IFS= read -r line; do
        printf '         %s\n' "$line"
    done || true
}

cron_remove() {
    { crontab -l 2>/dev/null | grep -v "$CRON_MARKER" || true; } | crontab -
    row 'Cron' 'desinstalado' "$C_GREEN"
}
