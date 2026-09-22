#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — recharge la recette avec une copie fraîche de la production.
#
# Enchaîne l'extraction (vps-pull.sh --local) et la restauration neutralisée
# (restore-local.sh), sans jamais laisser la copie envoyer quoi que ce soit :
# c'est restore-local.sh qui garantit ce point, en ne démarrant le planificateur
# qu'après avoir VÉRIFIÉ que les canaux sont coupés.
#
# À lancer sur le serveur, la production continuant de tourner : `pg_dump` prend
# un instantané cohérent sans la bloquer.
#
# Usage :
#   contrib/odice/staging/refresh.sh --from /opt/zammad-docker-compose \
#                                    --to   /opt/zammad-staging

set -o errexit
set -o nounset
set -o pipefail

SOURCE_DIR=''
TARGET_DIR=''
KEEP=2
ASSUME_YES=false

while [ $# -gt 0 ]; do
  case "$1" in
    --from)  SOURCE_DIR="$2"; shift 2 ;;
    --to)    TARGET_DIR="$2"; shift 2 ;;
    --keep)  KEEP="$2"; shift 2 ;;
    --yes)   ASSUME_YES=true; shift ;;
    -h|--help) sed -n '3,17p' "$0"; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; exit 1 ;;
  esac
done

[ -n "${SOURCE_DIR}" ] && [ -n "${TARGET_DIR}" ] || {
  echo "Erreur : --from <pile de production> et --to <pile de recette> sont obligatoires." >&2
  exit 1
}

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SOURCE_DIR="$(cd "${SOURCE_DIR}" && pwd)"
TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"

function env_get_at {
  local dir="$1" key="$2" default="${3:-}" value
  [ -f "${dir}/.env" ] || { printf '%s' "${default}"; return; }
  value="$(grep -E "^[[:space:]]*${key}=" "${dir}/.env" | tail -n1 | cut -d= -f2-)"
  value="${value%\"}"; value="${value#\"}"
  value="${value%\'}"; value="${value#\'}"
  printf '%s' "${value:-${default}}"
}

# Contrôle de cohérence avant de commencer. Les garde-fous qui comptent sont
# ceux de restore-local.sh — ceux-ci évitent simplement d'extraire plusieurs
# gigaoctets pour rien.
[ "$(env_get_at "${TARGET_DIR}" ODICE_ENVIRONMENT)" = 'staging' ] || {
  echo "Erreur : ${TARGET_DIR} ne se déclare pas ODICE_ENVIRONMENT=staging." >&2
  exit 1
}
[ "$(env_get_at "${SOURCE_DIR}" ODICE_ENVIRONMENT)" != 'staging' ] || {
  echo "Erreur : ${SOURCE_DIR} se déclare staging — la source doit être la production." >&2
  exit 1
}

STAMP="$(date -u +'%Y%m%dT%H%M%SZ')"
EXPORT_ROOT="${ODICE_REFRESH_DIR:-/var/tmp/odice-refresh}"
EXPORT_DIR="${EXPORT_ROOT}/${STAMP}"

mkdir -p "${EXPORT_DIR}"
# L'export contient l'intégralité du fichier client en clair. Il n'a rien à
# faire en lecture pour tout le monde sur /var/tmp.
chmod 700 "${EXPORT_ROOT}" "${EXPORT_DIR}"

cat <<INFO

  Rafraîchissement de la recette
  ─────────────────────────────
  Source (production) : ${SOURCE_DIR}   [$(env_get_at "${SOURCE_DIR}" ZAMMAD_FQDN)]
  Cible  (recette)    : ${TARGET_DIR}   [$(env_get_at "${TARGET_DIR}" ZAMMAD_FQDN)]
  Export temporaire   : ${EXPORT_DIR}

  La base de la recette sera DÉTRUITE et remplacée.
  La production n'est pas interrompue.

INFO

if [ "${ASSUME_YES}" != true ]; then
  read -r -p "  Taper « oui » pour continuer : " CONFIRM
  [ "${CONFIRM}" = "oui" ] || { echo "Annulé."; rmdir "${EXPORT_DIR}" 2>/dev/null || true; exit 1; }
fi

echo
echo "== 1/3 — Extraction depuis la production"
"${REPO_ROOT}/contrib/odice/vps-pull.sh" --local --path "${SOURCE_DIR}" --out "${EXPORT_DIR}"

echo
echo "== 2/3 — Restauration dans la recette, puis neutralisation"
# `--source-dir` active les contrôles croisés : projets Compose distincts,
# adresses distinctes. `--yes` ne saute que la saisie, jamais un garde-fou.
"${REPO_ROOT}/contrib/odice/restore-local.sh" \
  --from "${EXPORT_DIR}" \
  --dir "${TARGET_DIR}" \
  --source-dir "${SOURCE_DIR}" \
  --yes

echo
echo "== 3/3 — Purge des exports précédents (les ${KEEP} derniers sont gardés)"
# Décroissant, donc les plus récents d'abord : on supprime la queue de liste.
find "${EXPORT_ROOT}" -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n "+$(( KEEP + 1 ))" \
  | while read -r old; do
      echo "   suppression de ${old}"
      rm -rf "${old}"
    done

echo
echo "Recette rechargée : https://$(env_get_at "${TARGET_DIR}" ZAMMAD_FQDN)/"
