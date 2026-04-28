# Changelog

Todos los cambios notables del proyecto se documentan en este archivo.

El formato esta basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Versionado Semantico](https://semver.org/lang/es/). 

## [No publicado]

## [0.1.0] - 2026-04-28

### Agregado
- Inicio del versionado del repositorio. Anteriormente los cambios solo se reflejaban en
  los commits sin numero de version explicito. A partir de aqui cada caracteristica
  registrada en commit dispara un bump (patch o minor segun aplique). El consumidor
  principal de esta version es el dashboard `/inicio` de Mariachi, que la lee desde el
  registro `platforms_config.py` de mariachi-api.
