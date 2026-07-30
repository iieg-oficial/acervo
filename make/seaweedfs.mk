.PHONY: setup init-seaweedfs rotate-seaweedfs

##@ Acervo

setup: ## Crear el .env inicial desde el ejemplo
	@$(LIB)
	banner 'SETUP'
	if [ -f .env ]; then
		row 'Env' 'ya existe' "$$C_DIM" '.env'
	else
		cp .env.example .env
		row 'Env' 'creado' "$$C_GREEN" '.env'
		printf '\n  Edita .env con las credenciales reales antes de levantar.\n'
	fi
	rule
	printf '\n'

init-seaweedfs: ## Generar config/identities.json
	@$(LIB)
	banner 'INIT' 'identities'
	rule
	init_seaweedfs

rotate-seaweedfs: ## Rotar las passwords de S3, con selector de bucket
	@$(LIB)
	banner 'ROTATE' 'credenciales'
	bucket=$$(pick_bucket)
	confirm 'Rotar no actualiza a los consumidores: hay que propagar cada secret a mano.' 'rotar'
	rule
	if [ "$$bucket" = 'todos' ]; then
		init_seaweedfs -e ROTATE_FLAG=1
	else
		init_seaweedfs -e ROTATE_FLAG=1 -e TARGET_BUCKET="$$bucket"
	fi
