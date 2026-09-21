#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — point d'entrée du déploiement déclenché par la CI.
#
# Ce script est la SEULE chose que la clé de déploiement peut exécuter. La
# ligne correspondante d'~/.ssh/authorized_keys porte une commande forcée :
#
#   command="/opt/odice-ticketing/contrib/odice/switch/ci-deploy-entry.sh",\
#   no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAA…
#
# Sans cela, une clé déposée dans les secrets GitHub donnerait un shell complet
# sur le serveur de production à quiconque obtiendrait ces secrets. Ici elle ne
# peut que déployer un tag, et rien d'autre.
#
# La CI transmet le tag comme commande SSH ; OpenSSH le place dans
# SSH_ORIGINAL_COMMAND. Il est validé avant toute utilisation : c'est une
# donnée venue du réseau.

set -o errexit
set -o nounset
set -o pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ZDC="${ODICE_COMPOSE_DIR:-/opt/zammad-docker-compose}"
LOG="${REPO}/tmp/ci-deploy.log"
mkdir -p "$(dirname "${LOG}")"

function say {
  printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$1" | tee -a "${LOG}"
}

TAG="${SSH_ORIGINAL_COMMAND:-${1:-}}"

# Format attendu : 7.2.x-1a2b3c4d. Tout le reste est refusé — le tag sert à
# construire des commandes shell et une référence git.
if ! printf '%s' "${TAG}" | grep -qE '^[0-9]+\.[0-9]+\.[a-zA-Z0-9]+-[0-9a-f]{8}$'; then
  say "REFUS : tag invalide « ${TAG} »"
  exit 1
fi

SHA8="${TAG##*-}"
say "déploiement demandé : ${TAG}"

cd "${REPO}"

# Le `git checkout --force` plus bas écraserait sans prévenir un travail en
# cours dans ce dépôt. Sur un serveur il ne devrait jamais y en avoir — si c'est
# le cas, quelqu'un est en train d'y intervenir et on ne lui passe pas dessus.
if [ -n "$(git status --porcelain)" ]; then
  say 'REFUS : le dépôt a des modifications non commitées'
  exit 1
fi

# On se place exactement sur le commit que la CI a construit, pas sur la pointe
# de la branche : entre le build et ce déploiement, elle a pu avancer.
git fetch --quiet origin
if ! git rev-parse --verify --quiet "${SHA8}^{commit}" >/dev/null; then
  say "REFUS : commit ${SHA8} inconnu du dépôt"
  exit 1
fi
git checkout --quiet --force "${SHA8}"
say "dépôt positionné sur $(git log -1 --format='%h %s')"

ODICE_COMPOSE_DIR="${ZDC}" "${REPO}/contrib/odice/switch/deploy.sh" --dir "${ZDC}" 2>&1 | tee -a "${LOG}"
say "déploiement terminé : ${TAG}"
