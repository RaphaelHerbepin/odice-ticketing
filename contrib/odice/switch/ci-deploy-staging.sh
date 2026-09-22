#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Point d'entrée de la clé de déploiement de la RECETTE.
#
# Installé hors du dépôt par install-ci-entry.sh, et désigné par la commande
# forcée de ~/.ssh/authorized_keys :
#
#   command="/usr/local/sbin/odice-deploy-staging",no-port-forwarding,…  ssh-ed25519 AAAA…
#
# L'environnement est codé ICI, pas transmis par l'appelant : c'est ce qui rend
# impossible qu'une clé de recette atteigne la production.
set -o errexit -o nounset -o pipefail

export ENVIRONNEMENT='staging'
export REPO="${ODICE_REPO_DIR:-/opt/odice-ticketing-staging}"
export ZDC="${ODICE_COMPOSE_DIR:-/opt/zammad-staging}"

exec "${REPO}/contrib/odice/switch/ci-deploy-common.sh" "$@"
