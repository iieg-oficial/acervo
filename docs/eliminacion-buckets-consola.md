# Eliminación de Buckets y Usuarios desde Consola MinIO

Para eliminar un sistema por completo, debes borrar el bucket, el usuario y la política asociada. Este documento explica cómo hacerlo de manera segura desde la interfaz web (Consola) de MinIO.

## Acceder a la Consola
1. Ingresa a la URL de tu instancia: `https://iieg.jalisco.gob.mx/acervo/console/`
2. Inicia sesión con tus credenciales de administrador (las variables `MINIO_ACCESS_KEY` y `MINIO_SECRET_KEY` de tu archivo `.env`).

## Pasos para Eliminar

### 1. Eliminar el Bucket
**IMPORTANTE**: Para poder eliminar un bucket, este **debe estar completamente vacío**.
1. Ve a **Object Browser** en el menú izquierdo.
2. Selecciona el bucket que vas a eliminar.
3. Si tiene archivos o carpetas, selecciónalos todos y presiona el ícono del basurero para eliminarlos.
4. Una vez vacío, ve a **Buckets** en el menú izquierdo.
5. Haz clic en el bucket.
6. En la parte superior derecha, haz clic en el botón rojo **Delete**.
7. Escribe el nombre del bucket para confirmar y haz clic en **Delete Bucket**.

### 2. Eliminar el Usuario
1. Ve a **Users** en el menú izquierdo.
2. Encuentra al usuario asociado al bucket y haz clic sobre él.
3. En la parte superior derecha, haz clic en el botón rojo **Delete**.
4. Confirma la eliminación.

### 3. Eliminar la Política (Policy)
1. Ve a **Policies** en el menú izquierdo.
2. Encuentra la política o usa el buscador para encontrarla (ej. `policy-mi-nuevo-sistema`).
3. Haz clic sobre el nombre de la política.
4. En la parte superior derecha, haz clic en el botón rojo **Delete**.
5. Confirma la eliminación.
