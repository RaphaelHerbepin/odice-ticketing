# Odice — façade d'exploitation.
# L'amont n'a pas de Makefile : ce fichier ne peut donc pas entrer en conflit.
# La logique de construction vit dans contrib/odice/build.sh pour que la CI
# puisse l'appeler sans make.

SHELL       := /bin/bash
COMPOSE     := docker compose

# ZDC désigne l'installation Zammad à piloter. Comme toute variable
# d'environnement, `make` l'importe : un `export ZDC=/opt/zammad-docker-compose`
# une fois par session — ou dans ~/.bashrc — dispense de la répéter à chaque
# commande. `make ps ZDC=…` reste possible pour viser ponctuellement une autre
# pile. Sans elle, les cibles visent la pile de ce dépôt.
ZDC         ?=
# `cd` plutôt que `--project-directory` : COMPOSE_FILE peut chaîner plusieurs
# fichiers par des chemins relatifs, que Compose résout depuis le répertoire
# courant. Avec --project-directory, il les chercherait ici et échouerait.
COMPOSE_AT   = $(if $(ZDC),cd $(ZDC) && docker compose,$(COMPOSE))
SWITCH_DIR   = $(if $(ZDC),--dir $(ZDC),)
COMPOSE_DEV := docker compose -f docker-compose.dev.yml

.PHONY: .check-stack help build push up down restart logs ps console provision backup dev-up dev-down dev-logs lint-odice remote-inspect remote-pull restore-local image-tag deploy use-odice use-legacy use-legacy-dry-run which-version install-zdc refresh-staging maintenance-on maintenance-off maintenance-status deploy-production install-ci-entry

help: ## Affiche cette aide
	@echo "Pile visée : $(if $(ZDC),$(ZDC),ce dépôt — export ZDC=/opt/zammad-docker-compose pour en viser une autre)"
	@echo
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
# Garde-fou : sans ZDC exporté, ces cibles visent la pile de CE dépôt. Si elle
# n'est pas configurée (pas de .env), c'est presque toujours qu'on a oublié
# `export ZDC=…` — mieux vaut le dire que de laisser Compose échouer sur une
# erreur de variable manquante, qui n'oriente vers rien.
.check-stack:
	@if [ -z "$(ZDC)" ] && [ ! -f .env ]; then \
	  echo "Aucune pile visée."; \
	  echo; \
	  echo "  Ce dépôt n'a pas de .env, et ZDC n'est pas défini."; \
	  echo "  Pour piloter votre installation Zammad :"; \
	  echo; \
	  echo "    export ZDC=/opt/zammad-docker-compose"; \
	  echo; \
	  echo "  (à ajouter à ~/.bashrc pour ne plus y penser)"; \
	  exit 1; \
	fi

up: .check-stack ## Démarre la pile (make up ZDC=…)
	$(COMPOSE_AT) up -d

down: .check-stack ## Arrête la pile — SANS --remove-orphans, jamais
	$(COMPOSE_AT) down

restart: .check-stack ## Redémarre les services applicatifs
	$(COMPOSE_AT) restart zammad-railsserver zammad-scheduler zammad-websocket zammad-nginx

ps: .check-stack ## État des conteneurs
	$(COMPOSE_AT) ps

logs: .check-stack ## Suit les journaux (make logs S=zammad-railsserver)
	$(COMPOSE_AT) logs -f --tail=200 $(S)

console: .check-stack ## Ouvre une console Rails
	$(COMPOSE_AT) exec zammad-railsserver bundle exec rails console

provision: .check-stack ## Réapplique la configuration Odice (forcé)
	$(COMPOSE_AT) exec -T -e ODICE_PROVISION_FORCE=true zammad-railsserver \
	  bundle exec rake odice:provision

backup: .check-stack ## Déclenche une sauvegarde immédiate
	$(COMPOSE_AT) run --rm -e BACKUP_ONCE=true zammad-backup

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
image-tag: ## Affiche le tag d'image correspondant au commit courant
	@echo "$$(tr -d '\n' < VERSION)-$$(git rev-parse --short=8 HEAD)"

deploy: .check-stack ## Déploie l'image du commit courant (faire `git pull` avant)
	contrib/odice/switch/deploy.sh $(SWITCH_DIR)

use-odice: .check-stack ## Met la version Odice en service (sauvegarde la base d'abord)
	contrib/odice/switch/use-odice.sh $(SWITCH_DIR)

use-legacy: .check-stack ## Revient à la version historique (restaure la base d'avant bascule)
	contrib/odice/switch/use-legacy.sh $(SWITCH_DIR)

use-legacy-dry-run: .check-stack ## Montre ce que coûterait le retour arrière, sans rien changer
	contrib/odice/switch/use-legacy.sh $(SWITCH_DIR) --dry-run

which-version: .check-stack ## Affiche la version actuellement en service (make which-version ZDC=…)
	@echo "image   : $$($(COMPOSE_AT) ps --format '{{.Image}}' zammad-railsserver 2>/dev/null | head -n1)"
	@echo "version : $$($(COMPOSE_AT) exec -T zammad-railsserver cat /opt/zammad/VERSION 2>/dev/null || echo '(hors ligne)')"

install-zdc: ## Installe le complément Odice dans un zammad-docker-compose
	@test -n "$(ZDC)" || { echo "ZDC est obligatoire : export ZDC=/opt/zammad-docker-compose"; exit 1; }
	@contrib/odice/zdc/install.sh "$(ZDC)"

# ---------- Staging et maintenance ----------
STAGING ?= /opt/zammad-staging
PROD    ?= /opt/zammad-docker-compose

refresh-staging: ## Recharge le staging avec une copie neutralisée de la production
	@contrib/odice/staging/refresh.sh --from "$(PROD)" --to "$(STAGING)"

maintenance-on: .check-stack ## Coupe le site et affiche la page de maintenance (ZDC=…)
	@contrib/odice/switch/maintenance.sh on $(SWITCH_DIR)

maintenance-off: .check-stack ## Retire la page de maintenance et rend le site (ZDC=…)
	@contrib/odice/switch/maintenance.sh off $(SWITCH_DIR)

maintenance-status: .check-stack ## Dit si une maintenance est active (ZDC=…)
	@contrib/odice/switch/maintenance.sh status $(SWITCH_DIR)

deploy-production: .check-stack ## Mise en production complète, page de maintenance comprise
	@contrib/odice/switch/deploy-production.sh $(SWITCH_DIR)

install-ci-entry: ## (Re)installe les points d'entrée SSH hors du dépôt — à rejouer après toute modification
	@contrib/odice/switch/install-ci-entry.sh

# ---------- Qualité ----------
lint-odice: ## Lint des fichiers de thème Odice
	npx stylelint 'app/frontend/apps/*/styles/custom/*.css' 'app/assets/stylesheets/custom/*.css'
