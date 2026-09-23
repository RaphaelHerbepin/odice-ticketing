#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — charge un export d'instance Zammad dans une pile Docker de ce dépôt
# pour vérifier que les données remontent correctement dans le frontend Odice.
#
# La pile visée est celle de docker-compose.yml et du fichier d'environnement
# passé par --env-file (.env par défaut).
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

set -o errexit
set -o nounset
set -o pipefail

FROM_DIR=''
SANDBOX=true
ENV_FILE=''
TARGET_DIR=''
SOURCE_DIR=''
ASSUME_YES=false

while [ $# -gt 0 ]; do
  case "$1" in
    --from)           FROM_DIR="$2"; shift 2 ;;
    --dir)            TARGET_DIR="$2"; shift 2 ;;
    --source-dir)     SOURCE_DIR="$2"; shift 2 ;;
    --keep-channels)  SANDBOX=false; shift ;;
    --env-file)       ENV_FILE="$2"; shift 2 ;;
    --yes)            ASSUME_YES=true; shift ;;
    -h|--help)        sed -n '3,30p' "$0"; exit 0 ;;
    *)                echo "Option inconnue : $1" >&2; exit 1 ;;
  esac
done

[ -n "${FROM_DIR}" ] || { echo "Erreur : --from <répertoire> est obligatoire." >&2; exit 1; }
FROM_DIR="$(cd "${FROM_DIR}" && pwd)"

# Capturé AVANT tout déplacement : le montage des tâches rake s'y réfère, et un
# `cd` vers la pile cible le rendrait faux.
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

DB_FILE="$(find "${FROM_DIR}" -maxdepth 1 -name '*_zammad_db.psql.gz' | sort | tail -n1)"
[ -n "${DB_FILE}" ] || {
  echo "Erreur : aucun fichier *_zammad_db.psql.gz dans ${FROM_DIR}." >&2
  exit 1
}
FILES_FILE="$(find "${FROM_DIR}" -maxdepth 1 -name '*_zammad_files.tar.gz' | sort | tail -n1)"

# La pile visée n'est plus forcément celle de ce dépôt : une staging vit dans
# son propre répertoire, avec son propre .env et son propre projet Compose.
TARGET_DIR="$(cd "${TARGET_DIR:-${REPO_ROOT}}" 2>/dev/null && pwd)" || {
  echo "Erreur : répertoire de pile introuvable." >&2; exit 1; }
cd "${TARGET_DIR}"

ENV_FILE="${ENV_FILE:-${TARGET_DIR}/.env}"
[ -f "${ENV_FILE}" ] || { echo "Erreur : ${ENV_FILE} absent." >&2; exit 1; }

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

function env_get_at {
  local dir="$1" key="$2" default="${3:-}" value
  [ -f "${dir}/.env" ] || { printf '%s' "${default}"; return; }
  value="$(grep -E "^[[:space:]]*${key}=" "${dir}/.env" | tail -n1 | cut -d= -f2-)"
  value="${value%\"}"; value="${value#\"}"
  value="${value%\'}"; value="${value#\'}"
  printf '%s' "${value:-${default}}"
}

# Le nom de projet RÉELLEMENT résolu par Compose, seul à faire foi : c'est lui
# qui préfixe les volumes. Deux piles qui le partageraient partageraient leurs
# données, quelles que soient les intentions de l'appelant.
function project_name_at {
  (cd "$1" && docker compose --env-file "$1/.env" config --format json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])' 2>/dev/null) || printf ''
}

function refuse {
  echo >&2
  echo "REFUS — $1" >&2
  echo >&2
  echo "  Pile visée : ${TARGET_DIR}" >&2
  exit 1
}

TARGET_ENVIRONMENT="$(env_get ODICE_ENVIRONMENT)"
TARGET_PROJECT="$(project_name_at "${TARGET_DIR}")"

# ── Garde-fous ───────────────────────────────────────────────────────────────
#
# Ils ne remplacent pas la confirmation : ils la rendent superflue. On tape
# « oui » par réflexe, surtout la dixième fois ; ces contrôles-là, non. Chacun
# est bloquant, et `--yes` n'en saute aucun — il ne saute que la saisie.
#
# Le premier est le seul qui compte vraiment : une restauration ne doit JAMAIS
# pouvoir atteindre la production, quelle que soit la faute de frappe.
[ "${TARGET_ENVIRONMENT}" != 'production' ] \
  || refuse "cette pile se déclare « production » (ODICE_ENVIRONMENT)."

[ -n "${TARGET_ENVIRONMENT}" ] \
  || refuse "cette pile ne déclare aucun ODICE_ENVIRONMENT — impossible de savoir où l'on est."

[ -n "${TARGET_PROJECT}" ] \
  || refuse "Compose ne résout aucun nom de projet ici."

if [ -n "${SOURCE_DIR}" ]; then
  SOURCE_DIR="$(cd "${SOURCE_DIR}" && pwd)"
  SOURCE_PROJECT="$(project_name_at "${SOURCE_DIR}")"

  [ "${SOURCE_DIR}" != "${TARGET_DIR}" ] \
    || refuse "la source et la destination sont la même pile."
  [ "${SOURCE_PROJECT}" != "${TARGET_PROJECT}" ] \
    || refuse "source et destination partagent le projet Compose « ${TARGET_PROJECT} » — donc les mêmes volumes."
  [ "$(env_get_at "${SOURCE_DIR}" ZAMMAD_FQDN)" != "$(env_get ZAMMAD_FQDN)" ] \
    || refuse "source et destination portent le même ZAMMAD_FQDN."
fi

if [ "${SANDBOX}" = true ]; then
  [ -n "$(env_get ODICE_SANDBOX_FQDN)" ] \
    || refuse "ODICE_SANDBOX_FQDN n'est pas renseigné : la copie garderait l'adresse de l'instance d'origine."
fi

cat <<WARN

  ┌──────────────────────────────────────────────────────────────────────┐
  │  Cette opération DÉTRUIT la base de la pile visée                     │
  │  (DROP SCHEMA PUBLIC CASCADE) et la remplace par la copie fournie.    │
  └──────────────────────────────────────────────────────────────────────┘

  Base        : ${DB_FILE}
  Fichiers    : ${FILES_FILE:-aucun (pièces jointes supposées en base)}
  Pile        : ${TARGET_DIR}
  Projet      : ${TARGET_PROJECT}
  Environnement : ${TARGET_ENVIRONMENT}
  Base cible  : ${POSTGRESQL_DB}
  Adresse après neutralisation : $(env_get ODICE_SANDBOX_FQDN '<inchangée>')

WARN

if [ "${ASSUME_YES}" != true ]; then
  read -r -p "  Taper « oui » pour continuer : " CONFIRM
  [ "${CONFIRM}" = "oui" ] || { echo "Annulé."; exit 1; }
fi

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

# Démarrage ÉTAGÉ, et c'est le point le plus important de ce script.
#
# Un `dc up -d` global lancerait aussi `zammad-scheduler` — sur une base qui est,
# à cet instant précis, une copie intégrale de la production avec ses canaux
# e-mail ACTIFS. Pendant les minutes qui séparent la restauration de la
# neutralisation, la copie relèverait les vraies boîtes de l'assistance (en y
# marquant les messages comme lus), enverrait de vrais accusés de réception à de
# vrais clients, et déclencherait les relances automatiques.
#
# On ne démarre donc que ce qui restaure et migre. Le reste attend que
# `odice:sandbox` soit passé ET vérifié.
dc up -d zammad-redis zammad-memcached

# Elasticsearch seulement si la pile l'utilise. Le NOMMER explicitement suffirait
# à l'activer, même placé sous un profil inactif — c'est ainsi qu'un nœud de
# 1,5 Go s'est retrouvé démarré sur une pile qui l'avait délibérément coupé.
if [ "$(env_get ELASTICSEARCH_ENABLED true)" != 'false' ]; then
  dc up -d zammad-elasticsearch
fi

# `--force-recreate`, et non un simple `up -d`.
#
# `backup.sh` ne teste la présence du répertoire de restauration QU'À SON
# DÉMARRAGE (contrib/docker/backup.sh:112). Sur une pile déjà en marche, Compose
# répond « Running » sans rien recréer : les archives ne sont jamais vues, et le
# script attend indéfiniment un « Restore completed » qui ne viendra pas.
dc up -d --force-recreate zammad-backup

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

echo "   restauration terminée, migrations…"
# `zammad-init` porte les migrations ; il attend de lui-même la fin de la
# restauration (`check_no_restore_running`).
dc up -d zammad-init

# `run --rm --no-deps` et non `exec` : le serveur applicatif ne tourne pas encore,
# et c'est précisément ce qu'on veut à ce stade.
until dc run --rm --no-deps zammad-railsserver \
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
RAKE_MOUNT="${REPO_ROOT}/lib/tasks/odice:/opt/zammad/lib/tasks/odice:ro"

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

# ── Post-conditions ──────────────────────────────────────────────────────────
#
# Vérifiées, jamais supposées. Si la neutralisation n'a pas produit son effet,
# la pile reste ÉTEINTE : une staging éteinte n'a aucune conséquence, une
# staging qui écrit aux clients en a.
if [ "${SANDBOX}" = true ]; then
  echo
  echo "== Vérification avant d'ouvrir la pile"
  if ! dc run --rm --no-deps -v "${RAKE_MOUNT}" zammad-railsserver bundle exec rails r '
    errors = []
    errors << "canaux encore actifs (#{Channel.where(active: true).count})"     if Channel.where(active: true).any?
    errors << "déclencheurs encore actifs (#{Trigger.where(active: true).count})" if Trigger.where(active: true).any?
    errors << "automatisations encore actives (#{Job.where(active: true).count})" if Job.where(active: true).any?
    expected = ENV["ODICE_SANDBOX_FQDN"].to_s
    errors << "fqdn = #{Setting.get("fqdn")} au lieu de #{expected}" if expected.present? && Setting.get("fqdn") != expected
    abort("ÉCHEC : #{errors.join(" ; ")}") if errors.any?
    puts "  canaux, déclencheurs et automatisations coupés ; adresse réécrite."
  ' -e ODICE_SANDBOX_FQDN="$(env_get ODICE_SANDBOX_FQDN)"; then
    cat >&2 <<FAIL

REFUS d'ouvrir la pile : la neutralisation n'a pas produit son effet.

La base restaurée est une copie de production et ses canaux pourraient être
actifs. La pile reste volontairement éteinte. Corrigez, puis relancez ce
script — ne la démarrez pas à la main.
FAIL
    exit 1
  fi
fi

echo
echo "== Démarrage du reste de la pile"
dc up -d

echo
echo "Restauration terminée."
dc ps
echo
SITE="$(env_get ODICE_SANDBOX_HTTP_TYPE http)://$(env_get ODICE_SANDBOX_FQDN "localhost")"
echo "Ouvrez ${SITE} et vérifiez : nombre de tickets,"
echo "pièces jointes, utilisateurs, organisations, vues d'ensemble."
