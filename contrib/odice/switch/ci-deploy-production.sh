#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Point d'entrée de la clé de déploiement de la PRODUCTION.
#
# Installé hors du dépôt par install-ci-entry.sh, et désigné par la commande
# forcée de ~/.ssh/authorized_keys :
#
#   command="/usr/local/sbin/odice-deploy-production",no-port-forwarding,…  ssh-ed25519 AAAA…
#
# Déclenché par une étiquette de version, jamais par un push : c'est la seule
# différence de fond avec le staging, et elle tient dans la clé utilisée.
set -o errexit -o nounset -o pipefail

export ENVIRONNEMENT='production'
export REPO="${ODICE_REPO_DIR:-/opt/odice-ticketing}"
export ZDC="${ODICE_COMPOSE_DIR:-/opt/zammad-docker-compose}"

exec "${REPO}/contrib/odice/switch/ci-deploy-common.sh" "$@"
