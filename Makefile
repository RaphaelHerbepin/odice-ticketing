# Odice — façade d'exploitation.
# L'amont n'a pas de Makefile : ce fichier ne peut donc pas entrer en conflit.
# La logique de construction vit dans contrib/odice/build.sh pour que la CI
# puisse l'appeler sans make.

SHELL       := /bin/bash
COMPOSE     := docker compose
COMPOSE_DEV := docker compose -f docker-compose.dev.yml

.PHONY: rollback-dry-run help build push up down restart logs ps console provision backup dev-up dev-down dev-logs lint-odice remote-inspect remote-pull restore-local staging-up staging-down staging-logs staging-restore front-reload front-switch cutover rollback

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

# ---------- Pile de validation (sur le VPS, à côté de la pile historique) ----------
STAGING := docker compose -f docker-compose.yml -f docker-compose.staging.yml --env-file .env.staging

staging-up: ## Démarre la pile de validation (base séparée, domaine secondaire)
	$(STAGING) up -d
	@echo "Publiée sur 127.0.0.1:$$(grep -E '^ODICE_STAGING_PORT=' .env.staging | cut -d= -f2)"

staging-down: ## Arrête la pile de validation
	$(STAGING) down

staging-logs: ## Suit les journaux de la pile de validation (make staging-logs S=zammad-railsserver)
	$(STAGING) logs -f $(S)

staging-restore: ## Charge une copie de la production dans la pile de validation
	contrib/odice/restore-local.sh --from tmp/import --staging

# ---------- Bascule ----------
front-reload: ## Recharge Caddy après modification du Caddyfile ou de conf.d/
	COMPOSE_PROFILES=front $(COMPOSE) up -d --force-recreate odice-caddy

front-switch: ## Change l'amont du domaine canonique (make front-switch UPSTREAM=zammad-nginx:8080)
	@test -n "$(UPSTREAM)" || { echo "UPSTREAM= est obligatoire"; exit 1; }
	sed -i.bak -E 's|^ODICE_PROD_UPSTREAM=.*|ODICE_PROD_UPSTREAM=$(UPSTREAM)|' .env && rm -f .env.bak
	COMPOSE_PROFILES=front $(COMPOSE) up -d --force-recreate odice-caddy

cutover: ## Bascule vers la pile Odice — POINT DE NON-RETOUR
	contrib/odice/switch/cutover.sh

rollback: ## Revient à la pile historique (2 à 3 min)
	contrib/odice/switch/rollback.sh

rollback-dry-run: ## Répétition à blanc du retour arrière, sans rien modifier
	contrib/odice/switch/rollback.sh --dry-run

# ---------- Qualité ----------
lint-odice: ## Lint des fichiers de thème Odice
	npx stylelint 'app/frontend/apps/*/styles/custom/*.css' 'app/assets/stylesheets/custom/*.css'
