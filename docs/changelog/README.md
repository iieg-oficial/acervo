# Changelog del Acervo

Historial de cambios del servicio, **individualizado por versión mayor**. Cada línea
mayor tiene su propio archivo; dentro de cada uno, las versiones siguen el formato
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y
[Versionado Semántico](https://semver.org/lang/es/).

| Línea | Archivo | Rango | Resumen |
|-------|---------|-------|---------|
| **2.x** | [`v2.md`](v2.md) | `2.0.0` → | Acervo maduro: SeaweedFS consolidado, contrato `/ontoy` v2 y gestión administrable (schema `acervo` + UI de buckets). |
| **1.x** | [`v1.md`](v1.md) | `1.0.0` → `1.23.1` | De la salida a producción sobre MinIO a la migración a SeaweedFS. |

La versión vigente es la fuente de verdad en el archivo [`VERSION`](../../VERSION); su
fecha de release se lee de `docs/changelog/v<MAJOR>.md` (lo usa `make version-json`
para el sidecar `/ontoy`).

## Convención

- Cada `feat` sube **minor**; `fix`/`perf`/`refactor`/`chore`/`docs` suben **patch**.
- Un bump **mayor** marca un hito o corte de compatibilidad y abre un archivo nuevo
  (`v<N>.md`) con su propia sección `## [No publicado]`.
