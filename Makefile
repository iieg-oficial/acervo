GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
RESET  := $(shell tput -Txterm sgr0)

ENV ?= dev

ifeq ($(ENV),prod)
	COMPOSE_FILE := docker-compose.yml
	ENV_FILE     := .env
	MSG_ENV      := Producción
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
	@echo 'Uso: ${YELLOW}make <comando> [ENV=dev|prod]${RESET}'
	@echo '     (Por defecto ENV=dev)'
	@echo ''
	@echo '${GREEN}Comandos Generales:${RESET}'
	@echo '  ${YELLOW}make up${RESET}              - Inicia el entorno (en segundo plano)'
	@echo '  ${YELLOW}make build${RESET}           - Reconstruye e inicia el entorno'
	@echo '  ${YELLOW}make down${RESET}            - Detiene todos los contenedores'
	@echo '  ${YELLOW}make logs${RESET}            - Muestra logs en tiempo real'
	@echo '  ${YELLOW}make restart${RESET}         - Reinicia el entorno'
	@echo '  ${YELLOW}make restart-nginx${RESET}   - Reinicia solo Nginx (para aplicar cambios de IPs)'
	@echo ''
	@echo '${GREEN}Buckets y Datos:${RESET}'
	@echo '  ${YELLOW}make init-buckets${RESET}    - Crear buckets y usuarios por sistema'
	@echo '  ${YELLOW}make backup${RESET}          - Ejecutar respaldo manual'
	@echo '  ${YELLOW}make restore DATE=...${RESET} - Restaurar respaldo (ej: DATE=2026-01-15)'
	@echo '  ${YELLOW}make backup-list${RESET}     - Listar respaldos disponibles'
	@echo ''
	@echo '${GREEN}Seguridad:${RESET}'
	@echo '  ${YELLOW}make certs${RESET}           - Generar certificado SSL autofirmado'
	@echo '  ${YELLOW}make firewall-setup${RESET}  - Configurar UFW (requiere root)'
	@echo ''
	@echo '${GREEN}Cron:${RESET}'
	@echo '  ${YELLOW}make cron-install${RESET}    - Instalar cron de respaldos'
	@echo '  ${YELLOW}make cron-remove${RESET}     - Desinstalar cron de respaldos'
	@echo ''
	@echo '${GREEN}Utilidades:${RESET}'
	@echo '  ${YELLOW}make clean${RESET}           - Elimina contenedores, redes y volúmenes'
	@echo '  ${YELLOW}make shell-minio${RESET}     - Terminal del contenedor MinIO'
	@echo '  ${YELLOW}make shell-nginx${RESET}     - Terminal del contenedor Nginx (solo prod)'
	@echo '  ${YELLOW}make setup${RESET}           - Crea archivos .env iniciales'
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
	@echo "${YELLOW}Limpiando sistema (contenedores, redes y volúmenes)...${RESET}"
	docker compose -f docker-compose.dev.yml down -v --remove-orphans || true
	docker compose -f docker-compose.yml down -v --remove-orphans || true

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
	@bash scripts/backup.sh

restore:
	@if [ -z "$(DATE)" ]; then \
		echo "${YELLOW}Uso: make restore DATE=YYYY-MM-DD [BUCKET=nombre]${RESET}"; \
		exit 1; \
	fi
	@echo "${GREEN}Restaurando respaldo del $(DATE)...${RESET}"
	@bash scripts/restore.sh $(DATE) $(BUCKET)

backup-list:
	@echo "${GREEN}Respaldos disponibles:${RESET}"
	@echo ""
	@echo "${YELLOW}Diarios:${RESET}"
	@ls -la $(BACKUP_DIR)/daily/backup-*.tar.gz 2>/dev/null || echo "  (ninguno)"
	@echo "${YELLOW}Semanales:${RESET}"
	@ls -la $(BACKUP_DIR)/weekly/backup-*.tar.gz 2>/dev/null || echo "  (ninguno)"
	@echo "${YELLOW}Mensuales:${RESET}"
	@ls -la $(BACKUP_DIR)/monthly/backup-*.tar.gz 2>/dev/null || echo "  (ninguno)"

cron-install:
	@echo "${GREEN}Instalando cron de respaldos...${RESET}"
	@ACERVO_DIR=$$(pwd); \
	sed "s|/opt/acervo|$$ACERVO_DIR|g" scripts/backup-cron | crontab -
	@echo "${GREEN}Cron instalado. Respaldos diarios a las 2:00 AM${RESET}"

cron-remove:
	@echo "${YELLOW}Desinstalando cron de respaldos...${RESET}"
	@crontab -r 2>/dev/null || true
	@echo "${GREEN}Cron desinstalado${RESET}"

firewall-setup:
	@echo "${GREEN}Configurando firewall...${RESET}"
	@sudo bash scripts/firewall-setup.sh
