# Política de Respaldos de Acervo

El sistema Acervo cuenta con una política de respaldos automatizada que se encarga de guardar una copia completa de la información de todos los buckets y de limpiar copias antiguas para no saturar el almacenamiento del servidor.

## Cuándo se ejecutan
Los respaldos están programados mediante Cron para ejecutarse automáticamente:
- **Frecuencia:** Una vez al mes.
- **Día:** El día 1 de cada mes.
- **Hora:** 3:00 AM (hora del servidor).

*(Para instalar este cron debes ejecutar el comando `make cron-install` en la carpeta del proyecto).*

## Cómo se guardan
Cada vez que se ejecuta el proceso:
1. Se conecta interamente a MinIO.
2. Descarga una copia exacta (modo espejo) de todos los buckets administrados (ej. `portal`, `mapalab`, `mariachi`, `dataengine`).
3. Comprime todo en un único archivo de formato `.tar.gz` nombrado con la fecha de corte, por ejemplo: `backup-2026-04-01.tar.gz`.
4. El archivo se guarda en el servidor dentro de la ruta especificada por la variable `BACKUP_DIR` de tu archivo `.env` (generalmente `/backups/acervo/monthly/`).

## Política de Retención y Limpieza
Para prevenir que el disco se llene por completo con una acumulación infinita de copias, el sistema borra automáticamente los respaldos más viejos.

Esta política se configura en el archivo `.env`:
```env
BACKUP_RETENTION_MONTHS=2
```

Esto significa que:
- Solo se van a conservar los respaldos de los **últimos 2 meses** (60 días).
- Cualquier archivo en la carpeta de respaldos mensuales que tenga más de 2 meses de antigüedad será eliminado automáticamente cada vez que el script corra.
- Los logs de ejecución (`/logs/`) se conservan por 90 días antes de ser eliminados.

## Comandos Útiles

- **Ejecutar respaldo forzado ahora mismo:**
  ```bash
  make backup
  ```
- **Ver qué respaldos están disponibles en el sistema:**
  ```bash
  make backup-list
  ```
- **Restaurar un respaldo:**
  ```bash
  make restore DATE=YYYY-MM-DD
  # Ejemplo: make restore DATE=2026-04-01
  ```
