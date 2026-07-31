.DEFAULT_GOAL := help

MAKEFLAGS += --no-print-directory

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:

NETWORK_NAME := iieg-network
LIB := source make/lib.sh$(if $(wildcard make/repo.sh), && source make/repo.sh)

PROJECT_PROD := $(REPO_NAME)
PROJECT_DEV := $(if $(COMPOSE_DEV),$(REPO_NAME)-dev,)

UP_ENV := $(if $(COMPOSE_DEV),dev,prod)
UP_LABEL := $(if $(COMPOSE_DEV),desarrollo,)

COMPOSE_PROD_CMD := docker compose -p $(PROJECT_PROD) $(if $(ENV_PROD),--env-file $(ENV_PROD)) $(COMPOSE_PROD)
COMPOSE_DEV_CMD := $(if $(COMPOSE_DEV),docker compose -p $(PROJECT_DEV) $(if $(ENV_DEV),--env-file $(ENV_DEV)) $(COMPOSE_DEV))

UP_CMD ?= dc $(UP_ENV) up -d
UP_PROD_CMD ?= dc prod up -d
DEPLOY_CMD ?= dc prod up -d --build
DEPLOY_POST ?= $(UP_POST)

export REPO_NAME PROJECT_PROD PROJECT_DEV COMPOSE_PROD_CMD COMPOSE_DEV_CMD VERBOSE

.PHONY: help up deploy down restart logs status shell clean _up-prod

HELP_FILES = make/common.mk $(filter-out make/common.mk,$(MAKEFILE_LIST))

help:
	@printf '\n  \033[1m%s\033[0m\n' "$${REPO_NAME^^}"
	awk 'BEGIN { FS = ":.*?## " } \
	     /^##@/ { printf "\n  \033[2m%s\033[0m\n\n", substr($$0, 5); next } \
	     /^[a-zA-Z][a-zA-Z0-9_-]*:.*?## / { printf "    %-22s%s\n", $$1, $$2 }' $(HELP_FILES)
	printf '\n'

##@ Ciclo de vida

up: $(UP_PRE) ## Levantar sin reconstruir
	@$(LIB)
	banner 'UP' '$(UP_LABEL)'
	$(UP_GUARDS)
	run_step 'Up' $(UP_CMD)
	$(UP_POST)
	rule
	printf '\n'

_up-prod: $(UP_PRE)
	@$(LIB)
	banner 'UP' 'produccion'
	$(UP_GUARDS)
	run_step 'Up' $(UP_PROD_CMD)
	$(UP_POST)
	rule
	printf '\n'

deploy: $(DEPLOY_PRE) ## Actualizar, reconstruir y levantar produccion (VERBOSE=1 para ver el build)
	@$(LIB)
	start=$$(date +%s)
	banner 'DEPLOY' 'produccion'
	git_sync
	$(DEPLOY_GUARDS)
	rule
	run_step 'Down' dc prod down --remove-orphans
	run_step 'Build+Up' $(DEPLOY_CMD)
	$(DEPLOY_POST)
	rule
	total=$$(( $$(date +%s) - start ))
	printf '\n  %sDeploy completado%s  %02d:%02d\n\n' \
		"$$C_GREEN" "$$C_RESET" "$$((total / 60))" "$$((total % 60))"

down: ## Detener lo que este levantado
	@$(LIB)
	envs=$$(active_envs)
	if [ -z "$$envs" ]; then nothing_running 'DOWN'; exit 0; fi
	banner 'DOWN' "$$envs"
	for e in $$envs; do run_step "$$e" dc "$$e" down --remove-orphans; done
	rule
	printf '\n'

restart: ## Reiniciar el entorno activo
	@$(MAKE) down
	$(MAKE) up

clean: ## Detener y borrar volumenes
	@$(LIB)
	envs=$$(active_envs)
	banner 'CLEAN' "$${envs:-nada levantado}"
	confirm 'Esto elimina contenedores, redes y TODOS los volumenes del repo.' 'borrar'
	rule
	for e in $${envs:-prod}; do run_step "$$e" dc "$$e" down -v --remove-orphans; done
	$(CLEAN_EXTRA)
	rule
	printf '\n'

##@ Diagnostico

logs: ## Ver logs, con selector de servicio
	@$(LIB)
	env=$$(resolve_env)
	if [ -z "$$env" ]; then nothing_running 'LOGS'; exit 0; fi
	banner 'LOGS' "$$env"
	svc=$$(pick_service "$$env")
	rule
	if [ "$$svc" = 'todos' ]; then
		dc "$$env" logs -f --tail=100
	else
		dc "$$env" logs -f --tail=100 "$$svc"
	fi

status: ## Estado de los contenedores
	@$(LIB)
	envs=$$(active_envs)
	if [ -z "$$envs" ]; then nothing_running 'STATUS'; exit 0; fi
	banner 'STATUS' "$$envs"
	for e in $$envs; do
		printf '\n  %s%s%s\n' "$$C_DIM" "$$e" "$$C_RESET"
		dc "$$e" ps
	done
	printf '\n'
	$(STATUS_EXTRA)

shell: ## Terminal en un contenedor, con selector
	@$(LIB)
	env=$$(resolve_env)
	if [ -z "$$env" ]; then nothing_running 'SHELL'; exit 0; fi
	banner 'SHELL' "$$env"
	svc=$$(pick_service "$$env")
	if [ "$$svc" = 'todos' ]; then
		printf '  %sElige un servicio concreto.%s\n\n' "$$C_YELLOW" "$$C_RESET"
		exit 1
	fi
	rule
	dc "$$env" exec "$$svc" "$$(shell_for "$$env" "$$svc")"
