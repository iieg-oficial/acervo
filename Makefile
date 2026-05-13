GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
RESET  := $(shell tput -Txterm sgr0)

ENV ?= dev

ifeq ($(ENV),prod)
	COMPOSE_FILE := docker-compose.gateway.yml
	ENV_FILE     := .env.gateway
	MSG_ENV      := Producción (gateway)
else
	COMPOSE_FILE := docker-compose.dev.yml
	ENV_FILE     := .env.development
	MSG_ENV      := Desarrollo
endif

COMPOSE_CMD      := docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE)
COMPOSE_CMD_INIT := docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE) --profile init

.PHONY: help up build down logs restart clean shell-seaweedfs setup init-seaweedfs \
        rotate-seaweedfs migrate-from-minio backup restore backup-list cron-install \
        cron-remove

help:
	@echo ''
	@echo '${YELLOW}IIEG Acervo - Comandos disponibles${RESET}'
	@echo ''
	@echo 'Uso: ${YELLOW}make <comando> [ENV=dev|prod]${RESET}'
	@echo '     (Por defecto ENV=dev)'
	@echo ''
	@echo '${GREEN}Entornos disponibles:${RESET}'
	@echo '  ${WHITE}ENV=dev${RESET}                          - Desarrollo local (SeaweedFS expone puertos)'
	@echo '  ${WHITE}ENV=prod${RESET}                         - Produccion detras de gateway externo'
	@echo ''
	@echo '${GREEN}Generales:${RESET}'
	@echo '  ${YELLOW}up${RESET}                - Inicia el entorno en segundo plano'
	@echo '  ${YELLOW}build${RESET}             - Reconstruye e inicia el entorno'
	@echo '  ${YELLOW}down${RESET}              - Detiene todos los contenedores'
	@echo '  ${YELLOW}logs${RESET}              - Muestra logs en tiempo real'
	@echo '  ${YELLOW}restart${RESET}           - Reinicia el entorno'
	@echo ''
	@echo '${GREEN}Identidades y Buckets:${RESET}'
	@echo '  ${YELLOW}init-seaweedfs${RESET}    - Generar config/identities.json (passwords nuevas para users que no existen)'
	@echo '  ${YELLOW}rotate-seaweedfs${RESET}  - Rotar TODAS las passwords ${WHITE}[BUCKET=nombre]${RESET}'
	@echo ''
	@echo '${GREEN}Datos:${RESET}'
	@echo '  ${YELLOW}backup${RESET}            - Ejecutar respaldo manual'
	@echo '  ${YELLOW}restore${RESET}           - Restaurar respaldo ${WHITE}(DATE=YYYY-MM-DD [BUCKET=nombre])${RESET}'
	@echo '  ${YELLOW}backup-list${RESET}       - Listar respaldos disponibles'
	@echo '  ${YELLOW}migrate-from-minio${RESET} - One-shot: copiar datos de un volumen MinIO viejo a SeaweedFS'
	@echo ''
	@echo '${GREEN}Cron:${RESET}'
	@echo '  ${YELLOW}cron-install${RESET}      - Instalar cron de respaldos (mensual, dia 1 a las 3:00 AM)'
	@echo '  ${YELLOW}cron-remove${RESET}       - Desinstalar cron de respaldos'
	@echo ''
	@echo '${GREEN}Utilidades:${RESET}'
	@echo '  ${YELLOW}clean${RESET}             - Elimina contenedores, redes y volumenes'
	@echo '  ${YELLOW}shell-seaweedfs${RESET}   - Terminal del contenedor SeaweedFS'
	@echo '  ${YELLOW}setup${RESET}             - Crea archivos .env iniciales'
	@echo ''

up:
	@echo "${GREEN}Iniciando entorno de $(MSG_ENV)...${RESET}"
	$(COMPOSE_CMD) up -d

build:
	@echo "${GREEN}Reconstruyendo entorno de $(MSG_ENV)...${RESET}"
	$(COMPOSE_CMD) up -d --build

down:
	@echo "${YELLOW}Deteniendo entorno de $(MSG_ENV)...${RESET}"
	$(COMPOSE_CMD) down

logs:
	$(COMPOSE_CMD) logs -f

restart: down up

clean:
	@echo "${YELLOW}ADVERTENCIA: make clean borra TODOS los datos persistentes del entorno $(MSG_ENV).${RESET}"
	@echo "${YELLOW}Esto eliminara:${RESET}"
	@echo "  - Contenedores definidos en $(COMPOSE_FILE)"
	@echo "  - Redes creadas por el stack"
	@echo "  - Volumen seaweedfs_data (todos los buckets, objetos y datos)"
	@if [ -f "$(ENV_FILE)" ]; then \
		BUCKETS=$$(grep -E '^ACERVO_BUCKETS=' "$(ENV_FILE)" | cut -d= -f2- | tr -d '"'); \
		if [ -n "$$BUCKETS" ]; then \
			echo ""; \
			echo "${YELLOW}Buckets declarados en $(ENV_FILE):${RESET} $$BUCKETS"; \
		fi; \
	fi
	@echo ""
	@read -p "Escribe '$(ENV)' para confirmar el borrado: " CONFIRM; \
		if [ "$$CONFIRM" != "$(ENV)" ]; then \
			echo "${GREEN}Cancelado, no se borro nada.${RESET}"; \
			exit 1; \
		fi
	@echo "${YELLOW}Limpiando entorno de $(MSG_ENV) (contenedores, redes y volúmenes)...${RESET}"
	$(COMPOSE_CMD) down -v --remove-orphans

shell-seaweedfs:
	$(COMPOSE_CMD) exec seaweedfs /bin/sh

setup:
	@if [ ! -f .env.development ]; then \
		cp .env.development.example .env.development; \
		echo "${GREEN}Creado .env.development desde ejemplo${RESET}"; \
	else \
		echo "${YELLOW}.env.development ya existe${RESET}"; \
	fi
	@if [ ! -f .env.gateway ]; then \
		cp .env.gateway.example .env.gateway; \
		echo "${GREEN}Creado .env.gateway desde ejemplo${RESET}"; \
	else \
		echo "${YELLOW}.env.gateway ya existe${RESET}"; \
	fi

init-seaweedfs:
	@echo "${GREEN}Generando config/identities.json...${RESET}"
	$(COMPOSE_CMD_INIT) run --rm acervo-init

rotate-seaweedfs:
	@echo "${YELLOW}Rotando passwords (BUCKET=$(BUCKET))...${RESET}"
	$(COMPOSE_CMD_INIT) run --rm -e ROTATE_FLAG=1 -e TARGET_BUCKET=$(BUCKET) acervo-init

migrate-from-minio:
	@echo "${GREEN}Iniciando migracion one-shot desde volumen MinIO...${RESET}"
	@echo "${YELLOW}Requiere variables MIGRATE_MINIO_ACCESS_KEY/SECRET_KEY en $(ENV_FILE).${RESET}"
	@ENV_FILE=$(ENV_FILE) bash scripts/migrate-from-minio.sh

backup:
	@echo "${GREEN}Ejecutando respaldo manual...${RESET}"
	@ENV_FILE=$(ENV_FILE) bash scripts/backup.sh

restore:
	@echo "${GREEN}Restaurando respaldo...${RESET}"
	@ENV_FILE=$(ENV_FILE) bash scripts/restore.sh $(DATE) $(BUCKET)

backup-list:
	@echo "${GREEN}Respaldos disponibles:${RESET}"
	@echo ""
	@echo "${YELLOW}Mensuales:${RESET}"
	@bash -c 'source $(ENV_FILE); ls -la $${BACKUP_DIR:-/backups/acervo}/monthly/backup-*.tar.gz 2>/dev/null || echo "  (ninguno)"'

cron-install:
	@echo "${GREEN}Instalando cron de respaldos...${RESET}"
	@ACERVO_DIR=$$(pwd); \
	sed -e "s|/opt/acervo|$$ACERVO_DIR|g" -e "s|/bin/bash|/usr/bin/env ENV_FILE=$(ENV_FILE) /bin/bash|g" scripts/backup-cron | crontab -
	@echo "${GREEN}Cron instalado. Respaldos mensuales el dia 1 a las 3:00 AM${RESET}"

cron-remove:
	@echo "${YELLOW}Desinstalando cron de respaldos...${RESET}"
	@crontab -r 2>/dev/null || true
	@echo "${GREEN}Cron desinstalado${RESET}"
