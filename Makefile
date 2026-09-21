# Odice — façade d'exploitation.
# L'amont n'a pas de Makefile : ce fichier ne peut donc pas entrer en conflit.
# La logique de construction vit dans contrib/odice/build.sh pour que la CI
# puisse l'appeler sans make.

SHELL       := /bin/bash
COMPOSE     := docker compose
COMPOSE_DEV := docker compose -f docker-compose.dev.yml

.PHONY: help build push up down restart logs ps console provision backup dev-up dev-down dev-logs lint-odice remote-inspect remote-pull restore-local use-odice use-legacy use-legacy-dry-run which-version install-zdc

help: ## Affiche cette aide
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

# ---------- Développement ----------
dev-up: ## Démarre les services de développement (postgres, redis, memcached, elasticsearch)
	$(COMPOSE_DEV) up -d
	@echo "Ensuite : source docker/dev/env.sh && bin/setup --skip-server && bin/dev"

dev-down: ## Arrête les services de développement
	$(COMPOSE_DEV) down

dev-logs: ## Suit les journaux de développement
	$(COMPOSE_DEV) logs -f --tail=100 $(S)

# ---------- Image ----------
build: ## Construit l'image Odice
	@contrib/odice/build.sh

push: ## Construit et publie l'image
	@contrib/odice/build.sh --push

# ---------- Production ----------
up: ## Démarre la production
	$(COMPOSE) up -d

down: ## Arrête la production
	$(COMPOSE) down

restart: ## Redémarre les services applicatifs
	$(COMPOSE) restart zammad-railsserver zammad-scheduler zammad-websocket zammad-nginx

ps: ## État des conteneurs
	$(COMPOSE) ps

logs: ## Suit les journaux (make logs S=zammad-railsserver)
	$(COMPOSE) logs -f --tail=200 $(S)

console: ## Ouvre une console Rails
	$(COMPOSE) exec zammad-railsserver bundle exec rails console

provision: ## Réapplique la configuration Odice (forcé)
	$(COMPOSE) run --rm -e ODICE_PROVISION_FORCE=true odice-provision

backup: ## Déclenche une sauvegarde immédiate
	$(COMPOSE) run --rm -e BACKUP_ONCE=true zammad-backup

# ---------- Migration depuis une instance existante ----------
# HOST = utilisateur@serveur pour SSH ; REMOTE = répertoire du docker-compose.yml distant.
REMOTE ?= /opt/zammad-docker-compose

remote-inspect: ## Inspecte le serveur distant sans rien extraire (make remote-inspect HOST=root@vps.odice.fr)
	contrib/odice/vps-pull.sh --host $(HOST) --path $(REMOTE) --inspect

remote-pull: ## Extrait base et fichiers du serveur distant vers tmp/import
	contrib/odice/vps-pull.sh --host $(HOST) --path $(REMOTE)

restore-local: ## Charge l'export dans la pile locale pour vérification (DÉTRUIT la base locale)
	contrib/odice/restore-local.sh --from tmp/import

# ---------- Version en service ----------
# Une seule version tourne à la fois, sur la même base. Ces cibles gèrent la
# sauvegarde qui rend le retour arrière possible : ne changez pas le tag de
# l'image à la main.
#
# ZDC= désigne une installation zammad-docker-compose existante à piloter :
#   make use-odice ZDC=/opt/zammad-docker-compose
# Sans ZDC, c'est la pile de ce dépôt qui est visée.
ZDC ?=
SWITCH_DIR := $(if $(ZDC),--dir $(ZDC),)
COMPOSE_AT  = $(if $(ZDC),docker compose --project-directory $(ZDC),$(COMPOSE))

use-odice: ## Met la version Odice en service (sauvegarde la base d'abord)
	contrib/odice/switch/use-odice.sh $(SWITCH_DIR)

use-legacy: ## Revient à la version historique (restaure la base d'avant bascule)
	contrib/odice/switch/use-legacy.sh $(SWITCH_DIR)

use-legacy-dry-run: ## Montre ce que coûterait le retour arrière, sans rien changer
	contrib/odice/switch/use-legacy.sh $(SWITCH_DIR) --dry-run

which-version: ## Affiche la version actuellement en service (make which-version ZDC=…)
	@echo "image   : $$($(COMPOSE_AT) ps --format '{{.Image}}' zammad-railsserver 2>/dev/null | head -n1)"
	@echo "version : $$($(COMPOSE_AT) exec -T zammad-railsserver cat /opt/zammad/VERSION 2>/dev/null || echo '(hors ligne)')"

install-zdc: ## Installe le complément Odice dans un zammad-docker-compose (ZDC= requis)
	@test -n "$(ZDC)" || { echo "ZDC=/chemin/vers/zammad-docker-compose est obligatoire"; exit 1; }
	cp contrib/odice/zdc/docker-compose.override.yml $(ZDC)/
	@grep -q ODICE_IMAGE_REPO $(ZDC)/.env 2>/dev/null \
	  || cat contrib/odice/zdc/env.odice.example >> $(ZDC)/.env
	@echo "Complément installé. Relisez $(ZDC)/.env, puis : make use-odice ZDC=$(ZDC)"

# ---------- Qualité ----------
lint-odice: ## Lint des fichiers de thème Odice
	npx stylelint 'app/frontend/apps/*/styles/custom/*.css' 'app/assets/stylesheets/custom/*.css'
