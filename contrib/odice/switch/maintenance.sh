#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — page de maintenance pendant une mise en production.
#
# nginx-proxy répartit les requêtes entre TOUS les conteneurs déclarant un même
# VIRTUAL_HOST. Démarrer une page de maintenance à côté de l'application donnerait
# donc une alternance aléatoire entre les deux. Et détacher l'application du
# réseau ne tient pas : `docker compose up -d` la recrée au milieu du
# déploiement, avec son vhost retrouvé depuis le fichier compose.
#
# Le seul état qui survive à une recréation de conteneur est le `.env`. D'où
# l'indirection `VIRTUAL_HOST: ${ZAMMAD_VIRTUAL_HOST:-}` : la vider retire
# l'application des vhosts pour de bon, et laisse la page seule candidate.
#
# Usage :
#   contrib/odice/switch/maintenance.sh on  [--dir <pile>]
#   contrib/odice/switch/maintenance.sh off [--dir <pile>]
#   contrib/odice/switch/maintenance.sh status [--dir <pile>]

set -o errexit
set -o nounset
set -o pipefail

ACTION="${1:-}"
[ -n "${ACTION}" ] || { sed -n '3,20p' "$0"; exit 1; }
shift

# shellcheck source=contrib/odice/switch/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh" "$@"

MAINT_DIR="${REPO_ROOT}/contrib/odice/maintenance"
MAINT_FILE="${MAINT_DIR}/docker-compose.maintenance.yml"
STATE="${COMPOSE_DIR}/.odice-maintenance-state"

# Un projet Compose distinct de la pile : la page doit survivre au `down` de
# l'application, et disparaître sans emporter autre chose.
MAINT_PROJECT="odice-maintenance-$(basename "${COMPOSE_DIR}")"

function maint {
  docker compose -p "${MAINT_PROJECT}" -f "${MAINT_FILE}" "$@"
}

# Le vhost réellement publié, tel qu'il est ou tel qu'il était avant la coupure.
function published_host {
  local current saved
  current="$(env_get ZAMMAD_VIRTUAL_HOST)"
  saved="$(env_get ZAMMAD_VIRTUAL_HOST_SAVED)"
  printf '%s' "${current:-${saved}}"
}

# Attend que le domaine réponde ce qu'on attend. Une vérification active, et non
# un `sleep` : la régénération de la configuration par docker-gen est
# événementielle, son délai n'est pas prévisible, et supposer la bascule
# atomique est la meilleure façon de déployer sur un site encore ouvert.
function wait_for_state {
  local host="$1" expect="$2" limit="${3:-60}" i=0 code
  while [ "${i}" -lt "${limit}" ]; do
    code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "https://${host}/" || true)"
    case "${expect}" in
      maintenance)
        if [ "${code}" = '503' ] && curl -skI --max-time 5 "https://${host}/" | grep -qi '^x-odice-maintenance:'; then
          return 0
        fi
        ;;
      application)
        case "${code}" in 200|301|302|401|403) return 0 ;; esac
        ;;
    esac
    sleep 2
    i=$(( i + 1 ))
  done
  return 1
}

case "${ACTION}" in

  on)
    HOST="$(published_host)"
    [ -n "${HOST}" ] || {
      echo "Erreur : ni ZAMMAD_VIRTUAL_HOST ni ZAMMAD_VIRTUAL_HOST_SAVED dans ${ENV_FILE}." >&2
      echo "  Cette pile n'est pas exposée par nginx-proxy, ou l'override n'a pas été installé." >&2
      exit 1
    }

    # Idempotent : rejouer `on` ne doit pas écraser la valeur de retour par une
    # chaîne vide, ce qui rendrait le site définitivement invisible.
    if [ -z "$(env_get ZAMMAD_VIRTUAL_HOST)" ]; then
      echo "Maintenance déjà active pour ${HOST}."
      exit 0
    fi

    echo "== Passage en maintenance : ${HOST}"

    # La valeur de retour est écrite AVANT d'être détruite. Sans cela, un échec
    # entre les deux laisserait un .env sans vhost : le site resterait invisible
    # après un simple redémarrage du serveur, sans le moindre message d'erreur.
    env_set ZAMMAD_VIRTUAL_HOST_SAVED "${HOST}"
    env_set ZAMMAD_VIRTUAL_HOST ''
    dc up -d zammad-nginx

    MAINTENANCE_VIRTUAL_HOST="${HOST}" maint up -d

    echo "   attente de la page de maintenance…"
    wait_for_state "${HOST}" maintenance 60 || {
      echo "Erreur : la page de maintenance ne répond pas sur https://${HOST}/." >&2
      echo "  NE PAS DÉPLOYER. Remettre en service : $0 off --dir ${COMPOSE_DIR}" >&2
      exit 1
    }

    printf '%s\thost=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "${HOST}" > "${STATE}"
    echo "   page de maintenance active (503)."
    ;;

  off)
    HOST="$(env_get ZAMMAD_VIRTUAL_HOST_SAVED)"
    [ -n "${HOST}" ] || {
      echo "Erreur : aucune valeur de retour enregistrée (ZAMMAD_VIRTUAL_HOST_SAVED)." >&2
      echo "  Renseignez ZAMMAD_VIRTUAL_HOST à la main dans ${ENV_FILE}." >&2
      exit 1
    }

    echo "== Retour en service : ${HOST}"

    # La page part D'ABORD, le vhost revient ENSUITE. L'ordre inverse laisserait
    # quelques secondes durant lesquelles nginx-proxy répartirait entre une
    # application saine et la page de maintenance : un visiteur sur deux verrait
    # « maintenance » alors que le site est revenu. Deux secondes de 503 franc
    # valent mieux qu'un comportement qu'on ne peut pas expliquer.
    MAINTENANCE_VIRTUAL_HOST="${HOST}" maint down --remove-orphans 2>/dev/null || true

    env_set ZAMMAD_VIRTUAL_HOST "${HOST}"
    dc up -d zammad-nginx

    echo "   attente de l'application…"
    wait_for_state "${HOST}" application 90 || {
      echo "Erreur : https://${HOST}/ ne répond pas comme attendu." >&2
      echo "  L'application est peut-être en cours de démarrage ; vérifier : dc logs zammad-railsserver" >&2
      exit 1
    }

    rm -f "${STATE}"
    echo "   site rétabli."
    ;;

  status)
    if [ -f "${STATE}" ]; then
      echo "MAINTENANCE ACTIVE depuis $(cut -f1 "${STATE}")"
      echo "  $(cut -f2 "${STATE}")"
      exit 0
    fi
    if [ -z "$(env_get ZAMMAD_VIRTUAL_HOST)" ] && [ -n "$(env_get ZAMMAD_VIRTUAL_HOST_SAVED)" ]; then
      echo "ATTENTION : ZAMMAD_VIRTUAL_HOST est vide alors qu'aucune maintenance n'est enregistrée."
      echo "  Le site est invisible. Remettre en service : $0 off --dir ${COMPOSE_DIR}"
      exit 1
    fi
    echo "En service : $(published_host)"
    ;;

  *)
    echo "Action inconnue : ${ACTION} (on | off | status)" >&2
    exit 1
    ;;
esac
