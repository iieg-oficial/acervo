# Acervo

Servicio de almacenamiento de archivos para IIEG basado en SeaweedFS (compatible con la API S3).

## Requisitos

- Docker y Docker Compose
- Red Docker externa `iieg-network` (gestionada por el repo `gateway-hub`)

## Configuración inicial

```bash
make setup
# Editar .env con credenciales reales
make init-seaweedfs   # Genera config/identities.json (imprime nuevas creds por bucket)
```

## Uso

```bash
make up        # Levantar
make logs      # Ver logs
make down      # Detener
```

## Rotación de credenciales

```bash
make rotate-seaweedfs   # Rotar todas
make restart            # Aplicar la nueva config
```

## Respaldos

```bash
make backup    # Respaldo manual
make restore   # Lista los respaldos disponibles y restaura el que elijas
make cron      # Instalar o desinstalar el cron mensual (dia 1 a las 3:00 AM)
```

Rotación: `BACKUP_RETENTION_MONTHS` controla cuántos meses se conservan los tarballs (default 2).

## Migración desde MinIO (cerrada)

La migración MinIO → SeaweedFS cerró en 2.0.0: los targets `make migrate` y
`make migrate-from-minio`, sus scripts y las variables `MIGRATE_MINIO_*` ya no existen.
Detalles completos: `docs/changelog/v1.md` (1.22.0).

## Documentación

| Archivo | Contenido |
|--------|-----------|
| `docs/context.md` | Contexto técnico completo: arquitectura, componentes, decisiones de diseño |
| `docs/changelog/` | Historial de cambios, individualizado por versión mayor (`v1.md`, `v2.md`); índice en `README.md` |
| `docs/politica-respaldos.md` | Política operativa de respaldos |

## Comandos

```bash
make help    # Ver todos los comandos disponibles
```
