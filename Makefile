REPO_NAME    := acervo
COMPOSE_PROD := -f compose.yaml
ENV_PROD     := .env

UP_GUARDS     = ensure_network
DEPLOY_GUARDS = ensure_network

include make/common.mk
include make/seaweedfs.mk
include make/backup.mk
