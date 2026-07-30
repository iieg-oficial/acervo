C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_GREEN=$'\033[0;32m'
C_RED=$'\033[0;31m'
C_YELLOW=$'\033[0;33m'
C_CYAN=$'\033[0;36m'
C_RESET=$'\033[0m'

RULE='------------------------------------------'
SPINNER='⣾⣽⣻⢿⡿⣟⣯⣷'

banner() {
    printf '\n  %s%s — %s%s\n' "$C_BOLD" "${REPO_NAME^^}" "$1" "$C_RESET"
    [ -n "${2:-}" ] && printf '  %s%s%s\n' "$C_DIM" "$2" "$C_RESET"
    rule
}

rule() {
    printf '  %s%s%s\n' "$C_DIM" "$RULE" "$C_RESET"
}

row() {
    printf '  %-14s%s%-12s%s%s\n' "$1" "${3:-$C_GREEN}" "$2" "$C_RESET" "${4:+  $4}"
}

fail() {
    printf '  %s%-14s%s%s\n' "$C_RED" "${1%%:*}" "ERROR$C_RESET" ''
    printf '  %s\n' "${1#*:}"
    [ -n "${2:-}" ] && printf '\n  %s\n' "$2"
    exit 1
}

run_step() {
    local label=$1
    shift
    local log
    log=$(mktemp)
    "$@" >"$log" 2>&1 &
    local pid=$! i=0 start elapsed=0 frame rc
    start=$(date +%s)
    if [ -t 1 ]; then
        while kill -0 "$pid" 2>/dev/null; do
            elapsed=$(( $(date +%s) - start ))
            frame=${SPINNER:$((i % 8)):1}
            printf '\r\033[K  %s...%s%s  %s  %02d:%02d' \
                "$C_DIM" "$label" "$C_RESET" "$frame" "$((elapsed / 60))" "$((elapsed % 60))"
            sleep 0.15
            i=$((i + 1))
        done
        printf '\r\033[K'
    else
        while kill -0 "$pid" 2>/dev/null; do sleep 1; done
        elapsed=$(( $(date +%s) - start ))
    fi
    set +e
    wait "$pid"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
        printf '  %s%-14s%sok%s    %02d:%02d\n' \
            "$C_GREEN" "$label" "$C_RESET" '' "$((elapsed / 60))" "$((elapsed % 60))"
    else
        printf '  %s%-14s%sfail%s  %02d:%02d\n' \
            "$C_RED" "$label" "$C_RESET" '' "$((elapsed / 60))" "$((elapsed % 60))"
        tail -40 "$log" | while IFS= read -r line; do printf '         %s\n' "$line"; done
    fi
    rm -f "$log"
    return "$rc"
}

ensure_network() {
    local name=${1:-iieg-network}
    if docker network inspect "$name" >/dev/null 2>&1; then
        row 'Red' 'ya existe' "$C_GREEN" "($name)"
    else
        docker network create "$name" >/dev/null
        row 'Red' 'creada' "$C_GREEN" "($name)"
    fi
}

project_running() {
    [ -n "$(docker ps -q --filter "label=com.docker.compose.project=$1" 2>/dev/null)" ]
}

active_envs() {
    local found=''
    [ -n "${PROJECT_DEV:-}" ] && project_running "$PROJECT_DEV" && found="dev"
    project_running "$PROJECT_PROD" && found="${found:+$found }prod"
    printf '%s' "$found"
}

resolve_env() {
    local envs
    envs=$(active_envs)
    case "$envs" in
        *prod*) printf 'prod' ;;
        *dev*)  printf 'dev' ;;
        *)      printf '' ;;
    esac
}

compose_for() {
    if [ "$1" = 'dev' ]; then
        printf '%s' "$COMPOSE_DEV_CMD"
    else
        printf '%s' "$COMPOSE_PROD_CMD"
    fi
}

dc() {
    local env=$1
    shift
    local -a cmd
    read -ra cmd <<<"$(compose_for "$env")"
    "${cmd[@]}" "$@"
}

nothing_running() {
    banner "$1"
    row 'Estado' 'sin nada levantado' "$C_DIM"
    rule
    printf '\n'
}

pick() {
    local prompt=$1
    shift
    local -a options=("$@")
    local n=${#options[@]} i choice

    if [ "$n" -eq 0 ]; then
        return 1
    fi
    if [ "$n" -eq 1 ] || [ ! -t 0 ]; then
        printf '%s' "${options[0]}"
        return 0
    fi

    {
        for ((i = 0; i < n; i++)); do
            printf '   %d) %s\n' "$((i + 1))" "${options[i]}"
        done
        rule
        printf '  %s [1]: ' "$prompt"
    } >/dev/tty

    read -r choice </dev/tty || choice=''
    choice=${choice:-1}

    if ! [[ $choice =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$n" ]; then
        printf '  %sSeleccion invalida.%s\n' "$C_RED" "$C_RESET" >/dev/tty
        return 1
    fi
    printf '%s' "${options[$((choice - 1))]}"
}

pick_service() {
    local -a services
    mapfile -t services < <(dc "$1" ps --services 2>/dev/null | sort)
    if [ ${#services[@]} -eq 0 ]; then
        return 1
    fi
    pick 'Servicio' 'todos' "${services[@]}"
}

shell_for() {
    if dc "$1" exec "$2" test -x /bin/bash >/dev/null 2>&1; then
        printf '/bin/bash'
    else
        printf '/bin/sh'
    fi
}

confirm() {
    local answer
    printf '  %s%s%s\n' "$C_YELLOW" "$1" "$C_RESET"
    if [ ! -t 0 ]; then
        printf '  %sRequiere confirmacion interactiva; correlo desde una terminal.%s\n\n' \
            "$C_RED" "$C_RESET"
        exit 1
    fi
    printf "  Escribe '%s' para confirmar: " "$2"
    read -r answer </dev/tty || answer=''
    [ "$answer" = "$2" ] || {
        printf '  %sCancelado, no se toco nada.%s\n\n' "$C_GREEN" "$C_RESET"
        exit 1
    }
}

git_sync() {
    if [ ! -d .git ]; then
        row 'Git' 'n/a' "$C_DIM" 'no es un repo git'
        return 0
    fi
    local branch upstream local_sha remote_sha base sin_pushear sucios detalle
    branch=$(git branch --show-current 2>/dev/null || printf '')
    if [ -z "$branch" ]; then
        fail 'Git:HEAD detached, no se puede determinar la rama' \
             'Vuelve a una rama con: git checkout <rama>'
    fi
    sucios=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    detalle="$branch"
    [ "$sucios" -gt 0 ] && detalle="$branch, $sucios archivo(s) sin commitear"
    upstream=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || printf '')
    if [ -z "$upstream" ]; then
        row 'Git' 'n/a' "$C_DIM" "$detalle, sin upstream"
        return 0
    fi
    git fetch --quiet
    local_sha=$(git rev-parse HEAD)
    remote_sha=$(git rev-parse '@{u}')
    if [ "$local_sha" = "$remote_sha" ]; then
        if [ "$sucios" -gt 0 ]; then
            row 'Git' 'sin commitear' "$C_YELLOW" "$detalle"
        else
            row 'Git' 'al dia' "$C_GREEN" "$detalle"
        fi
        return 0
    fi
    base=$(git merge-base HEAD '@{u}')
    if [ "$base" = "$remote_sha" ]; then
        sin_pushear=$(git rev-list --count '@{u}..HEAD')
        row 'Git' 'sin pushear' "$C_YELLOW" "$detalle, $sin_pushear commit(s) locales"
        return 0
    fi
    if [ "$base" != "$local_sha" ]; then
        fail "Git:$branch divergio de $upstream" \
             'Resuelvelo a mano antes de desplegar: git log --oneline HEAD..@{u}'
    fi
    if git merge --ff-only --quiet '@{u}' 2>/dev/null; then
        row 'Git' 'actualizado' "$C_GREEN" "$detalle"
        return 0
    fi
    row 'Git' 'sin actualizar' "$C_YELLOW" \
        "$detalle; el fast-forward pisaria cambios locales, se despliega el arbol actual"
}
