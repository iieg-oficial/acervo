# Changelog

Todos los cambios notables del proyecto se documentan en este archivo.

El formato esta basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Versionado Semantico](https://semver.org/lang/es/).

La version `1.0.0` corresponde a la salida a produccion del servicio inicial
de MinIO. A partir de ahi cada `feat` dispara un bump minor y cada
`fix`/`perf`/`refactor`/`chore`/`docs` un bump patch.

## [No publicado]

## [1.19.0] - 2026-04-29

### Agregado
- **Flag `--rotate`** en `scripts/init-buckets.sh`: si el user del bucket ya existe, sobreescribe su password con una nueva aleatoria de 32 chars y la imprime. Combinable con un nombre de bucket para rotar uno solo (`./init-buckets.sh --rotate portal`) o con todos (`./init-buckets.sh --rotate`). Antes el unico camino para "recuperar" una password perdida era borrar el user (lo cual borraba sus policies attached). El flag tambien sirve para rotacion periodica.
- **Bucket `mariachi`** documentado en `.env.gateway.example` (`MINIO_BUCKETS=portal mapalab mariachi`). Mariachi gana su propio bucket para guardar sus assets propios (avatars de usuarios admin, imagenes que use el panel). Antes mariachi escribia con las creds root; ahora con `mariachi-user`. Bucket marcado publico (anonymous GetObject, igual patron que `portal` y `mapalab`).
- **Variable `ACERVO_PUBLIC_BUCKETS`** en `init-buckets.sh` (default `portal mapalab mariachi`) para configurar que buckets reciben anonymous GetObject. Antes la lista estaba hardcoded.

### Removido
- **Bucket `dateengine` (con typo)** del `.env.gateway.example`: mariachi nunca lo usaba en runtime. Si hay datos en GCP en ese bucket, no se tocan; basta con removerlo del `MINIO_BUCKETS` para que el init no lo procese.

### Notas migracion (cuando bajes 1.19.0 a la VM)

1. Agregar `mariachi` al `MINIO_BUCKETS` y quitar `dateengine` (si esta) en `.env.gateway`.
2. Correr `./scripts/init-buckets.sh --rotate` para rotar passwords de los buckets existentes y crear el nuevo `mariachi`. **Capturar las passwords que imprime** — solo se muestran una vez.
3. Pasar las passwords a `mariachi/.env.production` (variables `ACERVO_PORTAL_*`, `ACERVO_MAPALAB_*`, `ACERVO_MARIACHI_*`, `ACERVO_SIEEJ_*`).
4. Correr migracion de mariachi (>= v0.30.29) que agrega el proyecto/bucket en BD y desactiva `dateengine`.

---

## [1.18.3] - 2026-04-29

### Removido

- **`MINIO_SERVER_URL` del `.env.gateway.example`** y del servicio `minio` en `docker-compose.gateway.yml`. La variable se mantenia con default vacio "por si acaso", pero en modo gateway con path prefix (`/acervo/`) **siempre debe estar vacia** (path prefix rompe sigv4 en la S3 API). Tener la variable en el example invitaba a setearla incorrectamente.
- **`MINIO_SERVER_URL` del servicio `acervo-init`** en ambos compose files (`docker-compose.yml` y `docker-compose.gateway.yml`). El uso original sobrecargaba el nombre con dos semanticas distintas: la URL publica de S3 (sigv4) y el endpoint interno donde `mc` se conecta. Eran cosas distintas en una sola variable.

### Changed

- **`scripts/init-buckets.sh`** ahora usa `MINIO_INIT_ENDPOINT` con default `http://acervo-minio:9000` (alias DNS interno del container). El `mc` siempre se conecta por la red docker, no por internet, asi que no necesita resolver la URL publica. Si en el futuro alguien ejecuta el init desde fuera del compose (poco probable), puede pasar `MINIO_INIT_ENDPOINT=https://...` explicitamente.

### Notas migracion

Si un operador tiene `MINIO_SERVER_URL` seteado en su `.env.gateway` actual:
- Para el servicio **`minio`** del modo gateway: ya no se lee. Vaciarla o quitarla.
- Para el **modo standalone** (`docker-compose.yml`): la variable sigue usandose en el servicio `minio` (porque en standalone MinIO se sirve en la raiz del subdominio dedicado de acervo-nginx, sin path prefix, asi que sigv4 funciona). El init del modo standalone tampoco la usa ya.

---

## [1.18.2] - 2026-04-29

### Corregido

- **`.env.gateway.example`**: corregida la guia de `MINIO_SERVER_URL`. El bump 1.18.1 sugirio `MINIO_SERVER_URL=https://YOUR_DOMAIN/acervo`, lo cual rompe el login del console con `401 Unauthorized` (MinIO valida internamente con sigv4 y no soporta path prefix en la S3 API: el browser firma con `/acervo/...` en el path canonical pero el upstream calcula la firma con `/...` porque el proxy strip-ea el prefijo, provocando `SignatureDoesNotMatch`). Ahora el example deja `MINIO_SERVER_URL=` vacio con un comentario explicando que solo se debe setear si la S3 API tiene un subdominio dedicado (sin path). `MINIO_BROWSER_REDIRECT_URL` se mantiene con prefix porque solo afecta a redirects del console, no participa en sigv4.

### Notas

- El setup historico de acervo (modo `INFRA=standalone` con `acervo-nginx` propio) servia la S3 API en la raiz del host y por eso funcionaba sin issues. Al migrar a modo `INFRA=gateway` bajo path prefix, hay que dejar `MINIO_SERVER_URL` vacio o usar subdominio dedicado.

---

## [1.18.1] - 2026-04-29

### Corregido

- **`.env.gateway.example`**: actualizado el path de `MINIO_BROWSER_REDIRECT_URL` a `https://YOUR_DOMAIN/acervo/console` y `MINIO_SERVER_URL` a `https://YOUR_DOMAIN/acervo`. Antes decian `/console` y `/` respectivamente (legado de cuando acervo se exponia directamente en la raiz del dominio); el actual `gateway-hub` enruta acervo bajo `/acervo/console/`. Sin estos valores, MinIO genera URLs absolutas como `/static/...`, `/styles/...`, `/manifest.json`, que el browser pide con prefijo `/acervo/console/` (relativo al document) pero al llegar al upstream MinIO no las reconoce y devuelve `index.html` (SPA fallback). Resultado en el browser: `Refused to execute script ... MIME type ('text/html') is not executable`, `Refused to apply style ... MIME type ('text/html')` y `Manifest: Syntax error`. Comentario explicativo agregado al example.

---

## [1.18.0] - 2026-04-28

### Agregado
- Endpoint `/ontoy` expuesto por Nginx que devuelve `version.json` con
  `version`, `service` y `released_at` del servicio.
- Regla `version-json` en el `Makefile` que regenera `nginx/version.json`
  a partir del archivo `VERSION` y la fecha del ultimo commit; se ejecuta
  automaticamente como dependencia de `up` y `build`.

## [1.17.0] - 2026-04-28

### Agregado
- Deteccion dinamica del contenedor de MinIO y de su red durante el proceso de
  restore, evitando depender de nombres fijos.

## [1.16.0] - 2026-04-13

### Agregado
- Cabecera `Content-Security-Policy` ajustada en el proxy de la consola de
  MinIO para permitir el funcionamiento correcto de los assets.

## [1.15.1] - 2026-04-13

### Cambiado
- Capacidad de burst del rate limit de la consola de MinIO incrementada a
  1000 peticiones para soportar cargas elevadas.

## [1.15.0] - 2026-04-04

### Agregado
- Generacion de tokens JWT para Prometheus.
- Soporte para inicializacion selectiva de buckets via variables de entorno.

## [1.14.0] - 2026-03-30

### Agregado
- El script de restore admite un directorio de respaldo local.
- `.gitignore` actualizado para ignorar tarballs.

## [1.13.2] - 2026-03-30

### Corregido
- Eliminacion del directorio de respaldo mensual mediante contenedor Docker
  para hacerlo de forma segura, con limpieza del path vacio resultante.

## [1.13.1] - 2026-03-30

### Corregido
- Deteccion de la red de MinIO ajustada para manejar correctamente el
  formato con saltos de linea de `docker inspect`.

## [1.13.0] - 2026-03-25

### Agregado
- Tipo de autenticacion para Prometheus en MinIO.
- Configuracion de red externa para integracion con otros servicios.

## [1.12.0] - 2026-03-23

### Agregado
- Seleccion interactiva de la fecha de respaldo en el script de restore.
- Soporte correspondiente en el `Makefile`.

## [1.11.2] - 2026-03-23

### Corregido
- Resolucion correcta de `BACKUP_DIR` y valor por defecto al listar respaldos
  mensuales.

## [1.11.1] - 2026-03-23

### Cambiado
- Entrypoint de Docker definido explicitamente para los comandos `minio/mc`
  en los scripts de backup y restore.

## [1.11.0] - 2026-03-23

### Agregado
- Ruta del archivo de entorno configurable para los scripts de backup,
  restore y cron.

## [1.10.0] - 2026-03-23

### Agregado
- Estrategia de respaldo mensual con cron schedule actualizado, politica de
  retencion y documentacion asociada (`politica-respaldos.md`).

## [1.9.3] - 2026-03-23

### Agregado
- Guia para crear buckets y usuarios de MinIO desde la consola
  (`creacion-buckets-consola.md`).

## [1.9.2] - 2026-03-23

### Cambiado
- Target `clean` simplificado: se reemplazaron multiples `compose down` por
  un unico comando parametrizado.

## [1.9.1] - 2026-03-23

### Cambiado
- Placeholder de `CONSOLE_ALLOWED_IPS` en `.env.example` clarificado a
  ejemplos genericos de CIDR e IP.

## [1.9.0] - 2026-03-20

### Agregado
- Configuracion dinamica de `trusted proxies` en Nginx mediante una nueva
  variable de entorno.

## [1.8.1] - 2026-03-20

### Cambiado
- Mensaje de ayuda del `Makefile` mejorado: detalla entornos, clarifica el
  uso y refina las descripciones de comandos.

## [1.8.0] - 2026-03-20

### Agregado
- Opcion de infraestructura `gateway` con su propio `docker-compose`,
  `.env.example` y logica en el `Makefile` para seleccionar el tipo de
  infraestructura.

## [1.7.1] - 2026-03-19

### Cambiado
- Perfil `init` agregado al servicio `acervo-init`.
- Configuracion de Nginx simplificada al remover el bloque de redireccion
  HTTP.
- Patrones de ignore para `.env` generalizados.

## [1.7.0] - 2026-03-09

### Agregado
- Politica publica de `GetObject` extendida para incluir el bucket
  `mapalab`.

## [1.6.0] - 2026-02-18

### Agregado
- Politica publica de `GetObject` para el bucket `portal`.

## [1.5.0] - 2026-02-17

### Cambiado
- Limites de rate y burst incrementados en la zona de la consola de Nginx.

## [1.4.0] - 2026-02-17

### Agregado
- Bloque `location` en Nginx para los assets estaticos de la consola de
  MinIO.

## [1.3.4] - 2026-02-17

### Cambiado
- Comando de restart de Nginx forzado con recreacion del contenedor.

## [1.3.3] - 2026-02-17

### Corregido
- Removida la bandera `--insecure` del comando `mc admin user info`.
- Reformateo del attach de politicas.

## [1.3.2] - 2026-02-17

### Corregido
- Sintaxis del argumento de usuario en `mc admin policy attach`.

## [1.3.1] - 2026-02-17

### Corregido
- `cap_drop: ALL` cambiado para que tmpfs funcione correctamente.

## [1.3.0] - 2026-02-17

### Agregado
- Capabilities `CHOWN`, `SETUID`, `SETGID` y `DAC_OVERRIDE` agregadas al
  servicio en `docker-compose`.

## [1.2.4] - 2026-02-17

### Corregido
- Permisos `644` aplicados a los certificados SSL generados.
- Eliminada la bandera `--insecure` de los comandos de setup de MinIO.
- Host cambiado a HTTP para el setup interno.

## [1.2.3] - 2026-02-17

### Cambiado
- HTTP/2 habilitado explicitamente con directiva dedicada en la
  configuracion de Nginx.

## [1.2.2] - 2026-02-17

### Removido
- Limites de recursos `deploy` removidos de los servicios en
  `docker-compose.yml`.

## [1.2.1] - 2026-02-17

### Corregido
- Configuracion de limites de PIDs en Docker Compose ajustada para usar
  `pids` dentro del bloque `limits`.

## [1.2.0] - 2026-02-17

### Agregado
- Sistema integral de backup y restore.
- Configuracion de firewall.
- Control de acceso dinamico en Nginx.

## [1.1.0] - 2026-01-27

### Agregado
- Resolucion de host del dominio S3.
- Volumen para certificados SSL montado en el servicio MinIO.

## [1.0.0] - 2026-01-26

### Agregado
- Salida a produccion del servicio inicial de MinIO S3.
- `docker-compose` para entornos de desarrollo y produccion.
- Proxy Nginx con configuracion base.
- `Makefile` con targets de operacion.
- Documentacion inicial (`ARCHITECTURE.md`, `README.md`).
