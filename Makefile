# Makefile para IIEG Acervo
# Gestiona comandos de desarrollo y producción para Docker Compose

# Colores para output
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
RESET  := $(shell tput -Txterm sgr0)

# Entorno por defecto: dev
ENV ?= dev

# Configuración según entorno
ifeq ($(ENV),prod)
	COMPOSE_FILE := docker-compose.yml
	ENV_FILE     := .env
	MSG_ENV      := Producción
else
	COMPOSE_FILE := docker-compose.dev.yml
	ENV_FILE     := .env.development
	MSG_ENV      := Desarrollo
endif

.PHONY: help up build down logs restart clean shell-minio shell-nginx setup certs

## Muestra ayuda de comandos disponibles
help:
	@echo ''
	@echo '${YELLOW}IIEG Acervo - Comandos disponibles${RESET}'
	@echo ''
	@echo 'Uso: ${YELLOW}make <comando> [ENV=dev|prod]${RESET}'
	@echo '     (Por defecto ENV=dev)'
	@echo ''
	@echo '${GREEN}Comandos Generales:${RESET}'
	@echo '  ${YELLOW}make up${RESET}          - Inicia el entorno (en segundo plano)'
	@echo '  ${YELLOW}make build${RESET}       - Reconstruye e inicia el entorno'
	@echo '  ${YELLOW}make down${RESET}        - Detiene todos los contenedores'
	@echo '  ${YELLOW}make logs${RESET}        - Muestra logs en tiempo real'
	@echo '  ${YELLOW}make restart${RESET}     - Reinicia el entorno'
	@echo ''
	@echo '${GREEN}Utilidades:${RESET}'
	@echo '  ${YELLOW}make clean${RESET}       - Elimina contenedores, redes y volúmenes'
	@echo '  ${YELLOW}make shell-minio${RESET} - Entra a la terminal del contenedor MinIO'
	@echo '  ${YELLOW}make shell-nginx${RESET} - Entra a la terminal del contenedor Nginx (solo prod)'
	@echo '  ${YELLOW}make setup${RESET}       - Crea archivos .env iniciales si no existen'
	@echo '  ${YELLOW}make certs${RESET}       - Genera certificados SSL autofirmados'
	@echo ''

# =============================================================================
# COMANDOS PRINCIPALES
# =============================================================================

up:
	@echo "${GREEN}Iniciando entorno de $(MSG_ENV)...${RESET}"
	docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE) up -d

build:
	@echo "${GREEN}Reconstruyendo entorno de $(MSG_ENV)...${RESET}"
	docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE) up -d --build

down:
	@echo "${YELLOW}Deteniendo entorno de $(MSG_ENV)...${RESET}"
	docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE) down

logs:
	docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE) logs -f

restart: down up

# =============================================================================
# UTILIDADES
# =============================================================================

clean:
	@echo "${YELLOW}Limpiando sistema (contenedores, redes y volúmenes)...${RESET}"
	docker compose -f docker-compose.dev.yml down -v --remove-orphans || true
	docker compose -f docker-compose.yml down -v --remove-orphans || true

shell-minio:
	docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE) exec minio /bin/sh

shell-nginx:
	docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE) exec nginx /bin/sh

setup:
	@if [ ! -f .env.development ]; then \
		cp .env.development .env.development 2>/dev/null || echo "${YELLOW}.env.development ya configurado${RESET}"; \
	else \
		echo "${YELLOW}.env.development ya existe${RESET}"; \
	fi
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "${GREEN}Creado .env desde ejemplo${RESET}"; \
	else \
		echo "${YELLOW}.env ya existe${RESET}"; \
	fi

certs:
	@echo "${GREEN}Generando certificados SSL autofirmados...${RESET}"
	@mkdir -p nginx/ssl
	@openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
		-keyout nginx/ssl/s3.jalisco.gob.mx.key \
		-out nginx/ssl/s3.jalisco.gob.mx.crt \
		-subj "/C=MX/ST=Jalisco/L=Guadalajara/O=IIEG/CN=s3.jalisco.gob.mx" \
		-addext "subjectAltName=DNS:s3.jalisco.gob.mx" 2>/dev/null
	@echo "${GREEN}Certificados generados en nginx/ssl/${RESET}"
