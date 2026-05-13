# Acervo

Servicio de almacenamiento de archivos para IIEG basado en SeaweedFS (compatible con la API S3).

## Requisitos

- Docker y Docker Compose
- Red Docker externa `iieg-network` (gestionada por el repo `gateway-hub` en producción)

## Configuración inicial

```bash
make setup
# Editar .env.gateway (prod) o .env.development (dev) con credenciales reales
make init-seaweedfs ENV=prod   # Genera config/identities.json (imprime nuevas creds por bucket)
```

## Uso

```bash
make up ENV=prod        # Levantar produccion (modo gateway)
make up                 # Levantar dev
make logs               # Ver logs
make down               # Detener
```

## Rotación de credenciales

```bash
make rotate-seaweedfs ENV=prod                    # Rotar todas
make rotate-seaweedfs ENV=prod BUCKET=portal      # Rotar solo un bucket
make restart ENV=prod                             # Aplicar la nueva config
```

## Respaldos

```bash
make backup ENV=prod                              # Respaldo manual
make restore ENV=prod DATE=2026-05-13             # Restaurar todos los buckets
make restore ENV=prod DATE=2026-05-13 BUCKET=portal  # Restaurar un bucket
make backup-list ENV=prod                         # Listar respaldos
make cron-install ENV=prod                        # Cron mensual a las 3:00 AM
make cron-remove                                  # Desinstalar cron (cuidado: borra todo el crontab)
```

Rotación: `BACKUP_RETENTION_MONTHS` controla cuántos meses se conservan los tarballs (default 2).

## Migración desde MinIO (one-shot)

Si vienes de una versión anterior (1.21.x con MinIO):

```bash
# 1. Genera identidades y arranca SeaweedFS
make init-seaweedfs ENV=prod
make up ENV=prod

# 2. Configura MIGRATE_MINIO_ACCESS_KEY/SECRET_KEY en .env.gateway (root del MinIO viejo)
make migrate-from-minio ENV=prod
```

Detalles completos: `docs/CHANGELOG.md` (1.22.0).

## Documentación

| Archivo | Contenido |
|--------|-----------|
| `docs/context.md` | Contexto técnico completo: arquitectura, componentes, decisiones de diseño |
| `docs/CHANGELOG.md` | Historial de cambios |
| `docs/politica-respaldos.md` | Política operativa de respaldos |
| `docs/creacion-buckets-consola.md` | Histórico (vigente para v1.21.x, no aplica a 1.22+) |

## Comandos

```bash
make help    # Ver todos los comandos disponibles
```
