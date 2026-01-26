# Acervo

Servicio de almacenamiento de archivos para IIEG basado en MinIO (compatible con S3).

## Requisitos

- Docker y Docker Compose

## Configuración

```bash
# Producción
cp .env.example .env
# Editar .env con credenciales seguras

# Desarrollo
cp .env.development.example .env.development
# Editar .env.development
```

Para producción, colocar certificados SSL en `nginx/ssl/`:
- `s3.jalisco.gob.mx.crt`
- `s3.jalisco.gob.mx.key`

O generar autofirmados: `make certs`

## Uso

```bash
# Desarrollo
make up

# Producción
make up ENV=prod

# Ver logs
make logs

# Detener
make down
```

## Acceso

| Ambiente | URL |
|----------|-----|
| Dev | http://localhost:9000 (API), http://localhost:9001 (Consola) |
| Prod | https://s3.jalisco.gob.mx (API), https://s3.jalisco.gob.mx/console/ (Consola) |
