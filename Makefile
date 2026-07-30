GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
RESET  := $(shell tput -Txterm sgr0)

COMPOSE_FILE := docker-compose.yml
ENV_FILE     := .env

COMPOSE_CMD      := docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE)
COMPOSE_CMD_INIT := docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE) --profile init

.PHONY: help migrate up build down logs restart clean shell-seaweedfs setup \
        init-seaweedfs rotate-seaweedfs backup restore backup-list \
        cron-install cron-remove version-json

help:
	@echo ''
	@echo '${YELLOW}IIEG Acervo - Comandos disponibles${RESET}'
	@echo ''
	@echo 'Uso: ${YELLOW}make <comando>${RESET}'
	@echo ''
	@echo '${GREEN}Migracion (one-button):${RESET}'
	@echo '  ${YELLOW}migrate${RESET}           - Migracion completa MinIO -> SeaweedFS, propaga creds si todos los repos estan locales'
	@echo ''
	@echo '${GREEN}Lifecycle:${RESET}'
	@echo '  ${YELLOW}up${RESET}                - Inicia el entorno en segundo plano'
	@echo '  ${YELLOW}down${RESET}              - Detiene todos los contenedores'
	@echo '  ${YELLOW}restart${RESET}           - Reinicia el entorno'
	@echo '  ${YELLOW}logs${RESET}              - Muestra logs en tiempo real'
	@echo '  ${YELLOW}setup${RESET}             - Crea archivo .env inicial'
	@echo ''
	@echo '${GREEN}Identidades:${RESET}'
	@echo '  ${YELLOW}init-seaweedfs${RESET}    - Generar config/identities.json (passwords nuevas para users que no existen)'
	@echo '  ${YELLOW}rotate-seaweedfs${RESET}  - Rotar TODAS las passwords ${WHITE}[BUCKET=nombre]${RESET}'
	@echo ''
	@echo '${GREEN}Datos:${RESET}'
	@echo '  ${YELLOW}backup${RESET}            - Ejecutar respaldo manual'
	@echo '  ${YELLOW}restore${RESET}           - Restaurar respaldo ${WHITE}(DATE=YYYY-MM-DD [BUCKET=nombre])${RESET}'
	@echo '  ${YELLOW}backup-list${RESET}       - Listar respaldos disponibles'
	@echo ''
	@echo '${GREEN}Cron:${RESET}'
	@echo '  ${YELLOW}cron-install${RESET}      - Instalar cron de respaldos (mensual, dia 1 a las 3:00 AM)'
	@echo '  ${YELLOW}cron-remove${RESET}       - Desinstalar cron de respaldos'
	@echo ''
	@echo '${GREEN}Utilidades:${RESET}'
	@echo '  ${YELLOW}clean${RESET}             - Elimina contenedores, redes y volumenes'
	@echo '  ${YELLOW}shell-seaweedfs${RESET}   - Terminal del contenedor SeaweedFS'
	@echo '  ${YELLOW}version-json${RESET}      - Regenerar version-api/html/version.json desde VERSION'
	@echo ''

migrate:
	@bash scripts/migrate.sh

up: version-json
	@echo "${GREEN}Iniciando entorno...${RESET}"
	$(COMPOSE_CMD) up -d

build: version-json
	@echo "${GREEN}Reconstruyendo entorno...${RESET}"
	$(COMPOSE_CMD) up -d --build

version-json:
	@SERVICE=acervo; \
	 VERSION=$$(tr -d '[:space:]' < VERSION); \
	 MAJOR=$${VERSION%%.*}; \
	 CHANGELOG=docs/changelog/v$$MAJOR.md; \
	 RELEASED_AT=$$(grep -m1 "^## \[$$VERSION\]" $$CHANGELOG | sed -E 's/^## \[[^]]+\] - ([0-9-]+).*/\1/'); \
	 if [ -z "$$RELEASED_AT" ]; then echo "WARN: no se encontro entrada '## [$$VERSION] - YYYY-MM-DD' en $$CHANGELOG" >&2; fi; \
	 printf '{"version":"%s","service":"%s","released_at":"%s"}\n' "$$VERSION" "$$SERVICE" "$$RELEASED_AT" > version-api/html/version.json; \
	 echo "version.json -> $$VERSION ($$SERVICE, $$RELEASED_AT)"

down:
	@echo "${YELLOW}Deteniendo entorno...${RESET}"
	$(COMPOSE_CMD) down

logs:
	$(COMPOSE_CMD) logs -f

restart: down up

clean:
	@echo "${YELLOW}ADVERTENCIA: make clean borra TODOS los datos persistentes.${RESET}"
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
	@read -p "Escribe 'borrar' para confirmar: " CONFIRM; \
		if [ "$$CONFIRM" != "borrar" ]; then \
			echo "${GREEN}Cancelado, no se borro nada.${RESET}"; \
			exit 1; \
		fi
	@echo "${YELLOW}Limpiando (contenedores, redes y volumenes)...${RESET}"
	$(COMPOSE_CMD) down -v --remove-orphans

shell-seaweedfs:
	$(COMPOSE_CMD) exec seaweedfs /bin/sh

setup:
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "${GREEN}Creado .env desde ejemplo${RESET}"; \
		echo "${YELLOW}Edita .env con las credenciales reales antes de 'make migrate'${RESET}"; \
	else \
		echo "${YELLOW}.env ya existe${RESET}"; \
	fi

init-seaweedfs:
	@echo "${GREEN}Generando config/identities.json...${RESET}"
	$(COMPOSE_CMD_INIT) run --rm acervo-init

rotate-seaweedfs:
	@echo "${YELLOW}Rotando passwords (BUCKET=$(BUCKET))...${RESET}"
	$(COMPOSE_CMD_INIT) run --rm -e ROTATE_FLAG=1 -e TARGET_BUCKET=$(BUCKET) acervo-init

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
	( crontab -l 2>/dev/null | grep -v '# acervo-backup' ; \
	  sed -e "s|/opt/acervo|$$ACERVO_DIR|g" -e "s|/bin/bash|/usr/bin/env ENV_FILE=$(ENV_FILE) /bin/bash|g" scripts/backup-cron \
	) | crontab -
	@echo "${GREEN}Cron instalado. Respaldos mensuales el dia 1 a las 3:00 AM${RESET}"
	@crontab -l | grep '# acervo-backup'

cron-remove:
	@echo "${YELLOW}Desinstalando cron de respaldos...${RESET}"
	@( crontab -l 2>/dev/null | grep -v '# acervo-backup' ) | crontab -
	@echo "${GREEN}Cron desinstalado${RESET}"
