# Changelog

El changelog se individualizó **por versión mayor**. El contenido vive en
[`docs/changelog/`](changelog/):

- **Índice**: [`changelog/README.md`](changelog/README.md)
- **Serie 2.x** (actual): [`changelog/v2.md`](changelog/v2.md)
- **Serie 1.x** (histórico): [`changelog/v1.md`](changelog/v1.md)

> La versión vigente está en [`VERSION`](../VERSION). La fecha de cada release se lee
> de `docs/changelog/v<MAJOR>.md` (usado por `make version-json` para el sidecar `/ontoy`).

## [2.3.0] - 2026-09-24

Reparaciones de la auditoria de seguridad del 2026-09-24 (`context-ame-esta`,
`historial/2026-09-24-auditoria-seguridad.md`). Las versiones anteriores de la serie 2.x siguen en
`changelog/v2.md`.

### Corregido

- **Filer, master y volume de SeaweedFS ya no son alcanzables desde `iieg-network`.** `seaweedfs`
  sale de esa red y queda solo en `acervo_network`, con el alias `acervo-seaweedfs-interno`. Un
  servicio nuevo, `s3-proxy` (`nginx:1.30.4-alpine`, `stream`, uid 101, sin capacidades), entra a
  `iieg-network` con el alias `acervo-seaweedfs` y reenvia solo el 8333 (S3) y el 9091 (metricas, que
  huachicol sigue raspando). Los consumidores no cambian de URL. El 8333 publicado al host sigue en
  el contenedor de SeaweedFS. Probado con un SeaweedFS 4.23 desechable: desde la red compartida el
  8333 y el 9091 responden y el 9333, 8888, 8080 y los gRPC dan `Connection refused`.
  Se descarto `-ip=127.0.0.1 -ip.bind=127.0.0.1 -s3.ip.bind=0.0.0.0`: cierra lo mismo, pero en tres de
  doce arranques el filer no veia los volumenes y las lecturas S3 fallaban con `volume not found`
  hasta otro reinicio; con los flags actuales, ocho de ocho arranques salieron bien.
- **El secreto del admin ya no va en la linea de comandos.** `backup.sh` y `restore.sh` pasan la
  credencial a `mc` por `MC_HOST_acervo` (`-e` sin valor, tomado del entorno) en vez de interpolarla
  en `mc alias set` dentro de un `sh -c`. El helper `scripts/mc-host.sh` codifica la llave y el secreto
  para la URL.
- **Respaldos solo legibles por su dueno.** `backup.sh` corre con `umask 077` y deja el directorio de
  respaldos, `monthly/` y `logs/` en `700`.
- **`init-seaweedfs.sh` rechaza un secreto de admin debil**: vacio, de menos de 32 caracteres, igual
  al antiguo `replace_with_random_32_chars` o con el placeholder `<...>` del ejemplo. La access key
  tambien se rechaza si sigue siendo el placeholder.
- **La rotacion ya no imprime secretos.** `make rotate-seaweedfs` solo lista las identidades rotadas
  y como leer cada secreto de `config/identities.json` en el host. El archivo temporal se crea con
  `umask 077`.
- `.env.example`: `ACERVO_ADMIN_ACCESS_KEY` y `ACERVO_ADMIN_SECRET_KEY` pasan a placeholders; traian
  valores que `make setup` copiaba tal cual al `.env`.

### Cambiado

- `.env.example`: la arista de `ONTOY_PEER_CHECKS` a S4 pasa de `:6432` a `:5432`, porque pgbouncer ya
  no se publica fuera de la VM.
- El sidecar `version-api` ya no monta `docker.sock`; consulta contenedores por
  `DOCKER_HOST=tcp://docker-socket-proxy:2375` (`tecnativa/docker-socket-proxy:v0.5.0`,
  `CONTAINERS=1` y lo demas en 0, red interna `acervo-docker-api`) y corre como uid 65534.
- `ontoy_server.py` sincronizado con huachicol 2.18.0: 500 con texto fijo, tope de 8 hilos, timeout
  de 5 s, cache de 2 s y CPU sin sleep por peticion; desaparece `ONTOY_CPU_SAMPLE_SECONDS`.
