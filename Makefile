GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
RESET  := $(shell tput -Txterm sgr0)

ENV  ?= dev
INFRA ?= standalone

ifeq ($(ENV),prod)
	ifeq ($(INFRA),gateway)
		COMPOSE_FILE := docker-compose.gateway.yml
		ENV_FILE     := .env.gateway
		MSG_ENV      := Producción (gateway)
	else
		COMPOSE_FILE := docker-compose.yml
		ENV_FILE     := .env
		MSG_ENV      := Producción (standalone)
	endif
else
	COMPOSE_FILE := docker-compose.dev.yml
	ENV_FILE     := .env.development
	MSG_ENV      := Desarrollo
endif

COMPOSE_CMD := docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE)

.PHONY: help up build down logs restart restart-nginx clean shell-minio shell-nginx setup certs \
        init-buckets backup restore backup-list cron-install cron-remove firewall-setup

help:
	@echo ''
	@echo '${YELLOW}IIEG Acervo - Comandos disponibles${RESET}'
	@echo ''
	@echo 'Uso: ${YELLOW}make <comando> [ENV=dev|prod] [INFRA=standalone|gateway]${RESET}'
	@echo '     (Por defecto ENV=dev, INFRA=standalone)'
	@echo ''
	@echo '${GREEN}Entornos disponibles:${RESET}'
	@echo '  ${WHITE}ENV=dev${RESET}                          - Desarrollo local (MinIO directo)'
	@echo '  ${WHITE}ENV=prod INFRA=standalone${RESET}        - Produccion con Nginx propio (SSL, rate limit, IP filter)'
	@echo '  ${WHITE}ENV=prod INFRA=gateway${RESET}           - Produccion detras de gateway externo (sin Nginx)'
	@echo ''
	@echo '${GREEN}Generales:${RESET}'
	@echo '  ${YELLOW}up${RESET}                - Inicia el entorno en segundo plano'
	@echo '  ${YELLOW}build${RESET}             - Reconstruye e inicia el entorno'
	@echo '  ${YELLOW}down${RESET}              - Detiene todos los contenedores'
	@echo '  ${YELLOW}logs${RESET}              - Muestra logs en tiempo real'
	@echo '  ${YELLOW}restart${RESET}           - Reinicia el entorno'
	@echo '  ${YELLOW}restart-nginx${RESET}     - Reinicia solo Nginx ${WHITE}(standalone)${RESET}'
	@echo ''
	@echo '${GREEN}Buckets y Datos:${RESET}'
	@echo '  ${YELLOW}init-buckets${RESET}      - Crear buckets y usuarios por sistema'
	@echo '  ${YELLOW}backup${RESET}            - Ejecutar respaldo manual'
	@echo '  ${YELLOW}restore${RESET}           - Restaurar respaldo ${WHITE}(DATE=YYYY-MM-DD [BUCKET=nombre])${RESET}'
	@echo '  ${YELLOW}backup-list${RESET}       - Listar respaldos disponibles'
	@echo ''
	@echo '${GREEN}Seguridad:${RESET}                        ${WHITE}(solo standalone)${RESET}'
	@echo '  ${YELLOW}certs${RESET}             - Generar certificado SSL autofirmado'
	@echo '  ${YELLOW}firewall-setup${RESET}    - Configurar UFW ${WHITE}(requiere root)${RESET}'
	@echo ''
	@echo '${GREEN}Cron:${RESET}'
	@echo '  ${YELLOW}cron-install${RESET}      - Instalar cron de respaldos (mensual, dia 1 a las 3:00 AM)'
	@echo '  ${YELLOW}cron-remove${RESET}       - Desinstalar cron de respaldos'
	@echo ''
	@echo '${GREEN}Utilidades:${RESET}'
	@echo '  ${YELLOW}clean${RESET}             - Elimina contenedores, redes y volumenes'
	@echo '  ${YELLOW}shell-minio${RESET}       - Terminal del contenedor MinIO'
	@echo '  ${YELLOW}shell-nginx${RESET}       - Terminal del contenedor Nginx ${WHITE}(standalone)${RESET}'
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

restart-nginx:
	@echo "${GREEN}Reiniciando Nginx...${RESET}"
	$(COMPOSE_CMD) up -d --force-recreate nginx

clean:
	@echo "${YELLOW}Limpiando entorno de $(MSG_ENV) (contenedores, redes y volúmenes)...${RESET}"
	$(COMPOSE_CMD) down -v --remove-orphans

shell-minio:
	$(COMPOSE_CMD) exec minio /bin/sh

shell-nginx:
	$(COMPOSE_CMD) exec nginx /bin/sh

setup:
	@if [ ! -f .env.development ]; then \
		cp .env.development.example .env.development; \
		echo "${GREEN}Creado .env.development desde ejemplo${RESET}"; \
	else \
		echo "${YELLOW}.env.development ya existe${RESET}"; \
	fi
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "${GREEN}Creado .env desde ejemplo${RESET}"; \
	else \
		echo "${YELLOW}.env ya existe${RESET}"; \
	fi
	@if [ ! -f .env.gateway ]; then \
		cp .env.gateway.example .env.gateway; \
		echo "${GREEN}Creado .env.gateway desde ejemplo${RESET}"; \
	else \
		echo "${YELLOW}.env.gateway ya existe${RESET}"; \
	fi

certs:
	@echo "${GREEN}Generando certificado SSL autofirmado...${RESET}"
	@mkdir -p nginx/ssl
	@read -p "IP del servidor: " SERVER_IP; \
	openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
		-keyout nginx/ssl/acervo.key \
		-out nginx/ssl/acervo.crt \
		-subj "/C=MX/ST=Jalisco/L=Guadalajara/O=IIEG/CN=$$SERVER_IP" \
		-addext "subjectAltName=IP:$$SERVER_IP" 2>/dev/null; \
	chmod 644 nginx/ssl/acervo.key nginx/ssl/acervo.crt; \
	echo "${GREEN}Certificado generado para IP: $$SERVER_IP${RESET}"

init-buckets:
	@echo "${GREEN}Inicializando buckets y usuarios...${RESET}"
	$(COMPOSE_CMD) run --rm acervo-init

backup:
	@echo "${GREEN}Ejecutando respaldo manual...${RESET}"
	@ENV_FILE=$(ENV_FILE) bash scripts/backup.sh

restore:
	@if [ -z "$(DATE)" ]; then \
		echo "${YELLOW}Uso: make restore DATE=YYYY-MM-DD [BUCKET=nombre]${RESET}"; \
		exit 1; \
	fi
	@echo "${GREEN}Restaurando respaldo del $(DATE)...${RESET}"
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

firewall-setup:
	@echo "${GREEN}Configurando firewall...${RESET}"
	@sudo bash scripts/firewall-setup.sh
