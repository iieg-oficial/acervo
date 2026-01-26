# Arquitectura del Sistema

```
                         Internet
                             │
                             ▼
                   ┌─────────────────┐
                   │   Nginx Proxy   │
                   │  (acervo-nginx) │
                   │   :80 / :443    │
                   └────────┬────────┘
                            │
                            ▼
               ┌────────────────────────┐
               │   s3.jalisco.gob.mx    │
               │   /, /console/         │
               └───────────┬────────────┘
                           │
                           ▼
               ┌────────────────────────┐
               │     Acervo Network     │
               │  ┌──────────────────┐  │
               │  │      MinIO       │  │
               │  │  API: 9000       │  │
               │  │  Console: 9001   │  │
               │  └──────────────────┘  │
               └────────────────────────┘
```

## Dominio y Rutas

| Dominio | Ruta | Servicio | Descripción |
|---------|------|----------|-------------|
| s3.jalisco.gob.mx | / | acervo-minio | API S3 (almacenamiento) |
| s3.jalisco.gob.mx | /console/ | acervo-minio | Consola de administración MinIO |

## Conexión con Portal

El proyecto Portal (en otra MV) se conecta a MinIO usando:

```
MINIO_ENDPOINT=s3.jalisco.gob.mx
MINIO_PUBLIC_ENDPOINT=s3.jalisco.gob.mx
MINIO_USE_SSL=true
```

## Certificados SSL

Los certificados deben colocarse en `nginx/ssl/`:

```
nginx/ssl/
├── s3.jalisco.gob.mx.crt
└── s3.jalisco.gob.mx.key
```

Para generar certificados autofirmados: `make certs`

## Comandos

```bash
# Desarrollo
make up              # Inicia MinIO (puertos 9000, 9001)

# Producción
make up ENV=prod     # Inicia Nginx + MinIO (puertos 80, 443)
```
