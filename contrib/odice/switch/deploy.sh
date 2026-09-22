#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — déploie sur la pile l'image correspondant au commit courant du dépôt.
#
# Remplace l'enchaînement manuel : relever le tag dans la liste des exécutions
# CI, l'écrire dans le .env, redémarrer. Le tag n'est pas saisi mais CALCULÉ à
# partir du commit — il ne peut donc pas désigner autre chose que le code qu'on
# vient de récupérer.
#
# Usage :
#   git pull && contrib/odice/switch/deploy.sh
#   contrib/odice/switch/deploy.sh --dir /opt/zammad-docker-compose
#   contrib/odice/switch/deploy.sh --no-backup      # si un dump vient d'être pris

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=contrib/odice/switch/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BACKUP=true
while [ $# -gt 0 ]; do
  case "$1" in
    --no-backup) BACKUP=false; shift ;;
    --dir)       shift 2 ;;   # consommé par common.sh
    *)           echo "Option inconnue : $1" >&2; exit 1 ;;
  esac
done

VERSION="$(tr -d '\n' < "${REPO_ROOT}/VERSION")"
SHA8="$(git -C "${REPO_ROOT}" rev-parse --short=8 HEAD)"
TAG="${VERSION}-${SHA8}"
REPO="${ODICE_IMAGE_REPO:-$(env_get ODICE_IMAGE_REPO)}"

echo '== Image visée'
echo "  pile   : ${PILE} (${COMPOSE_DIR})"
echo "  commit : $(git -C "${REPO_ROOT}" log -1 --format='%h %s')"
echo "  image  : ${REPO}:${TAG}"

[ -n "${REPO}" ] || {
  echo "Erreur : ODICE_IMAGE_REPO n'est pas renseigné dans ${ENV_FILE}." >&2; exit 1; }

if [ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]; then
  echo
  echo "  Attention : le dépôt a des modifications non commitées. Le tag ${SHA8}" >&2
  echo "  décrit le dernier commit, pas ce qui est sur le disque." >&2
fi

echo
echo '== Disponibilité'
if ! docker pull "${REPO}:${TAG}" >/dev/null 2>&1; then
  cat >&2 <<FAIL
Erreur : ${REPO}:${TAG} est introuvable au registry.

  La CI a-t-elle terminé pour ce commit ?
    gh run list --repo <compte>/odice-ticketing --limit 3

  Un build prend 6 à 7 minutes. Rien n'a été modifié sur la pile.
FAIL
  exit 1
fi
echo '  image disponible'

CURRENT="$(env_get "${VAR_TAG}")"
if [ "${CURRENT}" = "${TAG}" ]; then
  echo
  echo "  Cette image est déjà celle en service. Redémarrage tout de même…"
fi

if [ "${BACKUP}" = true ]; then
  echo
  echo '== Sauvegarde'
  # Une mise à jour peut porter des migrations : on garde un point de retour,
  # même quand on reste sur la même famille d'images.
  dc up -d zammad-postgresql
  wait_for_postgres
  dump_database "pre-${SHA8}" >/dev/null
fi

echo
echo '== Démarrage'
env_set "${VAR_REPO}" "${REPO}"
env_set "${VAR_TAG}" "${TAG}"
dc up -d

wait_for_http "http://127.0.0.1:$(env_get NGINX_PORT 8080)/api/v1/getting_started" 600 || {
  echo 'La pile ne répond pas. Journaux de zammad-init :' >&2
  dc logs --tail 40 zammad-init >&2
  exit 1
}

echo
echo '== Configuration Odice'
# Sans cette étape, tout libellé ou réglage ajouté depuis la mise en service
# initiale n'atteignait jamais la production : la page Statistiques restait en
# anglais alors que ses traductions étaient au dépôt depuis des semaines.
# La tâche est idempotente et son compteur protège les réglages qu'un
# administrateur aurait modifiés entre-temps.
dc exec -T zammad-railsserver bundle exec rake odice:provision \
  || echo '  provisionnement en échec — à rejouer avec : make provision' >&2

echo
echo "== En service : ${REPO}:${TAG}"
echo "  $(dc exec -T zammad-railsserver cat /opt/zammad/VERSION 2>/dev/null || echo '(version illisible)')"
