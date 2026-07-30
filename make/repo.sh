CRON_MARKER='# acervo-backup'

init_seaweedfs() {
    dc prod --profile init run --rm "$@" acervo-init
}

pick_bucket() {
    local buckets
    buckets=$(grep -E '^ACERVO_BUCKETS=' .env 2>/dev/null | cut -d= -f2- | tr -d '"')
    if [ -z "$buckets" ]; then
        fail 'Buckets:no hay ACERVO_BUCKETS en .env' \
             'Definela con la lista de buckets antes de rotar.'
    fi
    pick 'Bucket' 'todos' $buckets
}

cron_install() {
    local dir
    dir=$(pwd)
    (
        crontab -l 2>/dev/null | grep -v "$CRON_MARKER"
        sed -e "s|/opt/acervo|$dir|g" \
            -e "s|/bin/bash|/usr/bin/env ENV_FILE=.env /bin/bash|g" scripts/backup-cron
    ) | crontab -
    row 'Cron' 'instalado' "$C_GREEN" 'mensual, dia 1 a las 3:00'
    crontab -l | grep "$CRON_MARKER" | while IFS= read -r line; do
        printf '         %s\n' "$line"
    done
}

cron_remove() {
    (crontab -l 2>/dev/null | grep -v "$CRON_MARKER") | crontab -
    row 'Cron' 'desinstalado' "$C_GREEN"
}
