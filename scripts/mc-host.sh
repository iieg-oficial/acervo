urlencode() {
    local LC_ALL=C s=$1 out='' c i
    for ((i = 0; i < ${#s}; i++)); do
        c=${s:i:1}
        case "$c" in
            [a-zA-Z0-9.~_-]) out+=$c ;;
            *) printf -v c '%%%02X' "'$c"; out+=$c ;;
        esac
    done
    printf '%s' "$out"
}

export_mc_host() {
    MC_HOST_acervo="http://$(urlencode "$ACERVO_ADMIN_ACCESS_KEY"):$(urlencode "$ACERVO_ADMIN_SECRET_KEY")@$1:8333"
    export MC_HOST_acervo
}
