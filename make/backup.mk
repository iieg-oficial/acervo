.PHONY: backup restore cron

##@ Respaldos

backup: ## Ejecutar un respaldo manual
	@$(LIB)
	banner 'BACKUP'
	rule
	ENV_FILE=.env bash scripts/backup.sh

restore: ## Restaurar un respaldo, con selector
	@$(LIB)
	banner 'RESTORE'
	rule
	ENV_FILE=.env bash scripts/restore.sh

cron: ## Instalar o desinstalar el cron de respaldos
	@$(LIB)
	banner 'CRON' 'respaldos'
	action=$$(pick 'Accion' 'instalar' 'desinstalar')
	rule
	if [ "$$action" = 'instalar' ]; then cron_install; else cron_remove; fi
	rule
	printf '\n'
