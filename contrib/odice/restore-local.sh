#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — charge un export d'instance Zammad dans une pile Docker de ce dépôt
# pour vérifier que les données remontent correctement dans le frontend Odice.
#
# Par défaut la pile locale (docker-compose.yml + .env). Avec --staging, la pile
# de validation (docker-compose.staging.yml + .env.staging), qui peut tourner
# sur le VPS aux côtés de la pile historique.
#
# Le conteneur `zammad-backup` sait déjà restaurer : il suffit de déposer les
# archives dans /var/tmp/zammad/restore. L'orchestration suit alors d'elle-même,
# parce que `zammad-init` commence par `check_no_restore_running`
# (bin/docker-entrypoint:28) — il attend la fin de la restauration, puis joue les
# migrations qui hissent le schéma restauré à la version de cette image.
#
# Usage :
#   contrib/odice/restore-local.sh --from tmp/import
#   contrib/odice/restore-local.sh --from tmp/import --keep-channels
#   contrib/odice/restore-local.sh --from tmp/import --staging

set -o errexit
set -o nounset
set -o pipefail

FROM_DIR=''
SANDBOX=true
ENV_FILE='.env'
COMPOSE_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --from)           FROM_DIR="$2"; shift 2 ;;
    --keep-channels)  SANDBOX=false; shift ;;
    --staging)        ENV_FILE='.env.staging'
                      COMPOSE_ARGS=(-f docker-compose.yml -f docker-compose.staging.yml)
                      shift ;;
    --env-file)       ENV_FILE="$2"; shift 2 ;;
    -h|--help)        sed -n '3,22p' "$0"; exit 0 ;;
    *)                echo "Option inconnue : $1" >&2; exit 1 ;;
  esac
done

[ -n "${FROM_DIR}" ] || { echo "Erreur : --from <répertoire> est obligatoire." >&2; exit 1; }
FROM_DIR="$(cd "${FROM_DIR}" && pwd)"

DB_FILE="$(find "${FROM_DIR}" -maxdepth 1 -name '*_zammad_db.psql.gz' | sort | tail -n1)"
[ -n "${DB_FILE}" ] || {
  echo "Erreur : aucun fichier *_zammad_db.psql.gz dans ${FROM_DIR}." >&2
  exit 1
}
FILES_FILE="$(find "${FROM_DIR}" -maxdepth 1 -name '*_zammad_files.tar.gz' | sort | tail -n1)"

cd "$(dirname "$0")/../.."
[ -f "${ENV_FILE}" ] || { echo "Erreur : ${ENV_FILE} absent à la racine du dépôt." >&2; exit 1; }

# Toutes les commandes passent par cette fonction : elle fixe le fichier
# compose et le fichier d'environnement, donc le PROJET visé. Sans cela, une
# restauration destinée à la pile de validation écraserait la production.
function dc {
  docker compose "${COMPOSE_ARGS[@]+"${COMPOSE_ARGS[@]}"}" --env-file "${ENV_FILE}" "$@"
}

# Le `.env` n'est PAS un script shell : Docker Compose y autorise des valeurs
# non quotées contenant des espaces (`ODICE_PRODUCT_NAME=Odice Helpdesk`), qu'un
# `source` interpréterait comme une commande — « Helpdesk: command not found ».
# On lit donc les quelques clés nécessaires sans rien exécuter.
function env_get {
  local key="$1" default="${2:-}" value
  value="$(grep -E "^[[:space:]]*${key}=" "${ENV_FILE}" | tail -n1 | cut -d= -f2-)"
  value="${value%\"}"; value="${value#\"}"   # guillemets doubles encadrants
  value="${value%\'}"; value="${value#\'}"   # guillemets simples encadrants
  printf '%s' "${value:-${default}}"
}

POSTGRESQL_DB="$(env_get POSTGRESQL_DB zammad_production)"
POSTGRESQL_USER="$(env_get POSTGRESQL_USER zammad)"
NGINX_PORT="$(env_get NGINX_PORT 8080)"

cat <<WARN

  ┌──────────────────────────────────────────────────────────────────────┐
  │  Cette opération DÉTRUIT la base locale (DROP SCHEMA PUBLIC CASCADE) │
  │  et la remplace par la copie de production.                          │
  └──────────────────────────────────────────────────────────────────────┘

  Base      : ${DB_FILE}
  Fichiers  : ${FILES_FILE:-aucun (pièces jointes supposées en base)}
  Cible     : projet compose « odice-ticketing », base ${POSTGRESQL_DB}

WARN
read -r -p "  Taper « oui » pour continuer : " CONFIRM
[ "${CONFIRM}" = "oui" ] || { echo "Annulé."; exit 1; }

echo
echo "== 1/5 — Démarrage de PostgreSQL"
dc up -d zammad-postgresql
until dc exec -T zammad-postgresql pg_isready -q -U "${POSTGRESQL_USER}"; do
  echo "   attente de PostgreSQL…"; sleep 2
done

# La restauration fait un DROP SCHEMA : la base doit exister au préalable. Sur
# une pile encore vierge, personne ne l'a créée.
echo "== 2/5 — Vérification de l'existence de la base ${POSTGRESQL_DB}"
if ! dc exec -T zammad-postgresql \
       psql -U "${POSTGRESQL_USER}" -lqt | cut -d'|' -f1 | grep -qw "${POSTGRESQL_DB}"; then
  echo "   création de ${POSTGRESQL_DB}…"
  dc exec -T zammad-postgresql createdb -U "${POSTGRESQL_USER}" "${POSTGRESQL_DB}"
fi

echo "== 3/5 — Dépôt des archives dans le volume de restauration"
# --user root : l'image tourne en 1000:1000 (Dockerfile:139) et ne crée pas
# /var/tmp/zammad, si bien que Docker initialise le volume nommé vide en
# root:root — l'utilisateur zammad ne peut alors même pas y créer un répertoire.
dc run --rm --no-deps --user root \
  --volume "${FROM_DIR}:/srv/import:ro" \
  --entrypoint bash zammad-backup -c '
    set -e
    mkdir -p /var/tmp/zammad/restore
    rm -f /var/tmp/zammad/restore/*
    cp /srv/import/*_zammad_db.psql.gz /var/tmp/zammad/restore/
    cp /srv/import/*_zammad_files.tar.gz /var/tmp/zammad/restore/ 2>/dev/null || true
    # On rend le volume à l utilisateur applicatif : la restauration doit lire
    # ces archives, puis renommer le répertoire restore en fin de course
    # (backup.sh:107), ce qui exige l écriture sur le parent.
    chown -R 1000:1000 /var/tmp/zammad
    ls -lh /var/tmp/zammad/restore/'

echo
echo "== 4/5 — Restauration, puis migrations vers cette version de Zammad"
# `zammad-backup` détecte le répertoire restore et restaure au lieu de sauvegarder
# (contrib/docker/backup.sh:114). `zammad-init` patiente puis migre.
# Horodatage pris AVANT le démarrage : les journaux d'une tentative précédente
# contiendraient des lignes d'erreur — ou un « Restore completed » — qui
# fausseraient la détection ci-dessous.
SINCE="$(date -u +'%Y-%m-%dT%H:%M:%S')"
dc up -d

# Le service porte `restart: unless-stopped` : un échec de restauration ne
# l'arrête pas, il le relance en boucle. On surveille donc le contenu des
# journaux, pas l'état du conteneur, et on borne l'attente.
RESTORE_TIMEOUT="${RESTORE_TIMEOUT:-7200}"
DEADLINE=$(( $(date +%s) + RESTORE_TIMEOUT ))
echo "   restauration en cours (délai maximum : ${RESTORE_TIMEOUT} s)…"
while true; do
  LOG="$(dc logs --since "${SINCE}" zammad-backup 2>/dev/null || true)"

  if grep -q 'Restore completed' <<< "${LOG}"; then
    break
  fi

  if grep -qE '^Error:|ERROR:|FATAL:' <<< "${LOG}"; then
    echo "Erreur pendant la restauration :" >&2
    dc logs --since "${SINCE}" --tail 40 zammad-backup >&2
    exit 1
  fi

  if [ "$(date +%s)" -ge "${DEADLINE}" ]; then
    echo "Erreur : délai dépassé. Journaux :" >&2
    dc logs --since "${SINCE}" --tail 40 zammad-backup >&2
    exit 1
  fi

  sleep 5
  printf '.'
done
echo

echo "   restauration terminée, attente des migrations…"
until dc exec -T zammad-railsserver \
        bundle exec rails r 'ActiveRecord::Migration.check_all_pending!' >/dev/null 2>&1; do
  echo "   migrations en cours…"; sleep 5
done

echo
echo "== 5/5 — Neutralisation et rebranding de la copie"
# Les tâches rake sont montées depuis le dépôt plutôt que prises dans l'image :
# celle-ci a pu être construite avant l'ajout ou la modification d'une tâche, et
# l'on obtiendrait alors « Don't know how to build task 'odice:sandbox' ». Le
# montage garantit qu'on exécute la version du dépôt, celle qu'on vient d'éditer.
# `run --no-deps` plutôt que `exec` : l'entrypoint retombe sur `exec "$@"` pour
# une commande non reconnue (bin/docker-entrypoint), et les services nécessaires
# tournent déjà.
RAKE_MOUNT="$(pwd)/lib/tasks/odice:/opt/zammad/lib/tasks/odice:ro"

# La base restaurée écrase les réglages de marque : product_logo, product_name et
# locale_default proviennent désormais de l'instance source. Il faut les réappliquer.
# Dans cet ordre : le provisioning réécrit product_name, la neutralisation y
# appose ensuite le suffixe « COPIE ».
dc run --rm --no-deps -v "${RAKE_MOUNT}" \
  -e ODICE_PROVISION_FORCE=1 zammad-railsserver bundle exec rake odice:provision

if [ "${SANDBOX}" = true ]; then
  dc run --rm --no-deps -v "${RAKE_MOUNT}" \
    -e ODICE_SANDBOX_CONFIRM=1 -e NGINX_PORT="${NGINX_PORT}" \
    -e ODICE_SANDBOX_FQDN="$(env_get ODICE_SANDBOX_FQDN "localhost:${NGINX_PORT}")" \
    -e ODICE_SANDBOX_HTTP_TYPE="$(env_get ODICE_SANDBOX_HTTP_TYPE http)" \
    -e ODICE_SANDBOX_PASSWORD="$(env_get ODICE_SANDBOX_PASSWORD)" \
    zammad-railsserver bundle exec rake odice:sandbox
else
  echo "   --keep-channels : canaux et automatisations laissés ACTIFS (dangereux hors production)."
fi

echo
echo "Restauration terminée."
dc ps
echo
SITE="$(env_get ODICE_SANDBOX_HTTP_TYPE http)://$(env_get ODICE_SANDBOX_FQDN "localhost")"
echo "Ouvrez ${SITE} et vérifiez : nombre de tickets,"
echo "pièces jointes, utilisateurs, organisations, vues d'ensemble."
