#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — corps commun des points d'entrée de déploiement continu.
#
# Ce fichier n'est jamais désigné par une commande forcée : ce sont
# ci-deploy-staging.sh et ci-deploy-production.sh, INSTALLÉS HORS DU DÉPÔT par
# install-ci-entry.sh, qui l'appellent.
#
# Pourquoi hors du dépôt : le déploiement fait `git checkout --force` sur le
# dépôt où vivait l'ancien point d'entrée. Bash lit un script au fil de son
# exécution, par décalage d'octets ; réécrire ce fichier pendant qu'il tourne
# fait poursuivre l'interpréteur sur un contenu qui a bougé sous lui. Le défaut
# était latent tant que le script ne changeait pas — il cessait de l'être au
# premier changement.
#
# Appelé avec : ENVIRONNEMENT, REPO, ZDC dans l'environnement.

set -o errexit
set -o nounset
set -o pipefail

: "${ENVIRONNEMENT:?ENVIRONNEMENT manquant}"
: "${REPO:?REPO manquant}"
: "${ZDC:?ZDC manquant}"

LOG="${REPO}/tmp/ci-deploy-${ENVIRONNEMENT}.log"
mkdir -p "$(dirname "${LOG}")"

function say {
  printf '%s [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "${ENVIRONNEMENT}" "$1" | tee -a "${LOG}"
}

# Un seul déploiement à la fois par environnement. Sans ce verrou, deux
# exécutions concurrentes se disputeraient le `git checkout --force` et
# arracheraient les fichiers sous le script de l'autre.
exec 9>"/var/lock/odice-deploy-${ENVIRONNEMENT}.lock"
if ! flock -w 900 9; then
  say "REFUS : un déploiement ${ENVIRONNEMENT} est déjà en cours depuis plus de 15 minutes"
  exit 1
fi

TAG="${SSH_ORIGINAL_COMMAND:-${1:-}}"

# Format attendu : 7.2.x-1a2b3c4d. Tout le reste est refusé — le tag sert à
# construire des commandes shell et une référence git.
#
# L'environnement n'apparaît PAS ici, et c'est délibéré : il est codé dans la
# commande forcée de la clé SSH, donc dans une donnée que l'appelant ne fournit
# pas. Rien à valider, rien à analyser, et une clé compromise côté staging ne
# peut pas viser la production.
if ! printf '%s' "${TAG}" | grep -qE '^[0-9]+\.[0-9]+\.[a-zA-Z0-9]+-[0-9a-f]{8}$'; then
  say "REFUS : tag invalide « ${TAG} »"
  exit 1
fi

SHA8="${TAG##*-}"
say "déploiement demandé : ${TAG}"

# La pile visée doit se déclarer de l'environnement attendu. Un ZDC mal
# renseigné dans le point d'entrée ne peut donc pas devenir un déploiement de
# staging sur la production, ni l'inverse.
ACTUAL="$(grep -E '^[[:space:]]*ODICE_ENVIRONMENT=' "${ZDC}/.env" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
if [ "${ACTUAL}" != "${ENVIRONNEMENT}" ]; then
  say "REFUS : ${ZDC} se déclare « ${ACTUAL:-<absent>} », attendu « ${ENVIRONNEMENT} »"
  exit 1
fi

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

if [ "${ENVIRONNEMENT}" = 'production' ]; then
  ODICE_COMPOSE_DIR="${ZDC}" "${REPO}/contrib/odice/switch/deploy-production.sh" \
    --dir "${ZDC}" --tag "${TAG}" 2>&1 | tee -a "${LOG}"
else
  # Le staging se déploie sans page de maintenance : personne n'y est en train
  # de travailler, et une coupure de deux minutes y est sans conséquence.
  ODICE_COMPOSE_DIR="${ZDC}" "${REPO}/contrib/odice/switch/deploy.sh" \
    --dir "${ZDC}" 2>&1 | tee -a "${LOG}"
fi

say "déploiement terminé : ${TAG}"
