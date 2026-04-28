# Changelog

Todos los cambios notables del proyecto se documentan en este archivo.

El formato esta basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Versionado Semantico](https://semver.org/lang/es/).

La version `1.0.0` corresponde a la salida a produccion del servicio inicial
de MinIO. A partir de ahi cada `feat` dispara un bump minor y cada
`fix`/`perf`/`refactor`/`chore`/`docs` un bump patch.

## [No publicado]

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
