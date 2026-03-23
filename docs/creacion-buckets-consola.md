# Creación de Buckets y Usuarios desde Consola MinIO

Esta guía explica cómo crear un nuevo bucket y asignarle un usuario con permisos exclusivos usando la interfaz web (Consola) de MinIO.

## Pasos

### 1. Acceder a la Consola
1. Ingresa a la URL de tu instancia: `https://iieg.jalisco.gob.mx/acervo/console/`
2. Inicia sesión con tus credenciales de administrador (las variables `MINIO_ACCESS_KEY` y `MINIO_SECRET_KEY` de tu archivo `.env`).

### 2. Crear el Bucket
1. En el menú lateral izquierdo, ve a la sección **Buckets**.
2. Haz clic en el botón azul **Create Bucket** (arriba a la derecha).
3. Ingresa un **Bucket Name** (ejemplo: `mi-nuevo-sistema`).
   * *Nota: Los nombres de bucket deben estar en minúsculas, sin espacios y pueden contener guiones.*
4. Deja las demás opciones por defecto y haz clic en **Create Bucket**.

### 3. Crear una Política (Policy)
Para que el usuario solo pueda ver su propio bucket, necesitamos crear una política.
1. En el menú lateral izquierdo, bajo la sección "Identity", ve a **Policies**.
2. Haz clic en **Create Policy**.
3. En "Policy Name", ingresa un nombre claro, como `policy-mi-nuevo-sistema`.
4. En el campo de JSON, pega lo siguiente y **reemplaza `NOMBRE_DEL_BUCKET`** por el nombre exacto que usaste en el paso anterior:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:*"],
            "Resource": [
                "arn:aws:s3:::NOMBRE_DEL_BUCKET",
                "arn:aws:s3:::NOMBRE_DEL_BUCKET/*"
            ]
        }
    ]
}
```
5. Haz clic en **Save**.

### 4. Crear el Usuario y Asignar la Política
1. En el menú lateral izquierdo, ve a **Users**.
2. Haz clic en **Create User**.
3. Completa los campos:
   * **Access Key**: El nombre de usuario (ejemplo: `mi-nuevo-sistema-user`).
   * **Secret Key**: Una contraseña segura (guárdala en un lugar seguro, ya que **solo se muestra una vez**).
4. En la sección "Assign Policies", **selecciona la casilla** de la política que creaste en el Paso 3 (ejemplo: `policy-mi-nuevo-sistema`).
5. Haz clic en **Save**.

### 5. Configurar el Backend
Usa en el backend (tu API u otra aplicación) las credenciales que acabas de crear:
- **Usuario/Access Key**: `mi-nuevo-sistema-user`
- **Contraseña/Secret Key**: La que definiste en el paso anterior.
- **Bucket**: `mi-nuevo-sistema`

El usuario ahora podrá subir, borrar y listar archivos *únicamente* dentro de ese bucket.

---

*Alternativa: Puedes hacer el proceso de creación de manera automática utilizando por línea de comandos el script `init-buckets.sh` como se indica en el `Makefile` (`make init-buckets`).*
