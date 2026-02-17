# Acervo

Servicio de almacenamiento de archivos para IIEG basado en MinIO (compatible con S3).

## Requisitos

- Docker y Docker Compose
- UFW (para firewall en producción)

## Configuración

```bash
make setup
# Editar .env con credenciales y IPs reales
make certs
```

## Uso

```bash
make up ENV=prod          # Levantar producción
make init-buckets         # Crear buckets y usuarios
make logs                 # Ver logs
make down                 # Detener
```

## Acceso

| Ambiente | API | Consola |
|----------|-----|---------|
| Dev | http://localhost:9000 | http://localhost:9001 |
| Prod | https://SERVER_IP | https://SERVER_IP/console/ |

## Seguridad

- **HTTPS** con certificado autofirmado por IP (`make certs`)
- **Consola restringida** por IP via `CONSOLE_ALLOWED_IPS` en `.env`
- **Rate limiting**: API 50r/s, consola 5r/s
- **Hardening Docker**: `no-new-privileges`, `cap_drop: ALL`, filesystem read-only en nginx, límites de memoria/CPU
- **Red interna**: MinIO no expone puertos al host, solo Nginx es público
- **Firewall UFW**: `make firewall-setup` restringe puertos 80/443 a IPs de `ALLOWED_SERVER_IPS`
- **Aislamiento por bucket**: cada sistema (mapalab, dateengine, portal) tiene su usuario y política IAM

## Respaldos

```bash
make backup               # Respaldo manual
make restore DATE=2026-01-15          # Restaurar todos los buckets
make restore DATE=2026-01-15 BUCKET=mapalab  # Restaurar un bucket
make backup-list          # Listar respaldos
make cron-install         # Cron diario a las 2:00 AM
make cron-remove          # Desinstalar cron
```

Rotación: diarios (`BACKUP_RETENTION_DAYS`), semanales (`BACKUP_RETENTION_WEEKS`), mensuales (`BACKUP_RETENTION_MONTHS`).

## Comandos

```bash
make help                 # Ver todos los comandos disponibles
```
