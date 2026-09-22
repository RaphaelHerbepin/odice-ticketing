#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — mise en production, page de maintenance comprise.
#
# Ce que fait ce script et que `deploy.sh` ne fait pas : couper proprement
# l'accès public pendant la bascule, vérifier que la coupure est effective avant
# de toucher à quoi que ce soit, et ne rendre le site qu'après contrôle.
#
# Usage :
#   contrib/odice/switch/deploy-production.sh --dir /opt/zammad-docker-compose --tag 7.2.x-1a2b3c4d

set -o errexit
set -o nounset
set -o pipefail

TAG=''
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    *)     ARGS+=("$1"); shift ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=contrib/odice/switch/common.sh
source "${HERE}/common.sh" "${ARGS[@]+"${ARGS[@]}"}"

require_environment production

HOST="$(env_get ZAMMAD_VIRTUAL_HOST)"
[ -n "${HOST}" ] || {
  echo "Erreur : ZAMMAD_VIRTUAL_HOST est vide dans ${ENV_FILE}." >&2
  echo "  Une maintenance est peut-être restée active : ${HERE}/maintenance.sh status --dir ${COMPOSE_DIR}" >&2
  exit 1
}

IMAGE="$(env_get "${VAR_REPO}")"
[ -n "${TAG}" ] || TAG="$(env_get "${VAR_TAG}")"

echo "== Mise en production de ${TAG} sur ${HOST}"

# L'image est téléchargée AVANT toute coupure. La tirer après aurait allongé
# l'indisponibilité de tout le temps de transfert — et, si le registre est
# injoignable, on aurait coupé le site pour rien.
echo "== 1/6 — Téléchargement de l'image"
docker pull "${IMAGE}:${TAG}" >/dev/null || {
  echo "Erreur : ${IMAGE}:${TAG} introuvable au registre. Rien n'a été touché." >&2
  exit 1
}

echo "== 2/6 — Passage en maintenance"
"${HERE}/maintenance.sh" on --dir "${COMPOSE_DIR}"

# La sauvegarde est prise APRÈS la coupure : elle constitue alors un point de
# retour exact, aucune écriture ne pouvant plus survenir entre elle et la
# bascule. En contrepartie sa durée s'ajoute à l'indisponibilité — à surveiller
# si la base grossit.
echo "== 3/6 — Sauvegarde de la base"
ensure_rollback_dir
dc up -d zammad-postgresql
wait_for_postgres
dump_database "pre-${TAG}"

echo "== 4/6 — Déploiement"
if ! ODICE_COMPOSE_DIR="${COMPOSE_DIR}" "${HERE}/deploy.sh" --dir "${COMPOSE_DIR}" --no-backup; then
  cat >&2 <<FAIL

ÉCHEC du déploiement. La page de maintenance RESTE EN PLACE — rendre le domaine
à une application cassée serait pire.

  Diagnostic :   cd ${COMPOSE_DIR} && docker compose logs --tail 60 zammad-railsserver
  Remise en service, une fois corrigé :
                 ${HERE}/maintenance.sh off --dir ${COMPOSE_DIR}
  Retour arrière : voir contrib/odice/BASCULE.md
FAIL
  exit 1
fi

# Contrôle sur le CONTENEUR, pas sur le domaine : celui-ci sert encore la page
# de maintenance à cet instant, et l'interroger ne dirait rien de l'application.
echo "== 5/6 — Contrôle avant réouverture"
if ! dc exec -T zammad-nginx curl -fsS -H "Host: ${HOST}" \
      http://localhost:8080/api/v1/getting_started >/dev/null 2>&1; then
  # 403 est une réponse valide de cette route sur une instance déjà configurée.
  if ! dc exec -T zammad-nginx sh -c \
        "curl -s -o /dev/null -w '%{http_code}' -H 'Host: ${HOST}' http://localhost:8080/api/v1/getting_started" \
        2>/dev/null | grep -qE '^(200|403)$'; then
    echo "Erreur : l'application ne répond pas derrière la maintenance. Page laissée en place." >&2
    exit 1
  fi
fi

RUNNING="$(dc exec -T zammad-railsserver cat /opt/zammad/VERSION 2>/dev/null | tr -d '\r\n' || true)"
echo "   version en service : ${RUNNING:-inconnue}"

echo "== 6/6 — Retour en service"
"${HERE}/maintenance.sh" off --dir "${COMPOSE_DIR}"

echo
echo "Mise en production terminée : ${TAG} sur https://${HOST}/"
