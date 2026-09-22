# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — fonctions partagées par use-odice.sh et use-legacy.sh.
# Ce fichier se source, il ne s'exécute pas.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# La pile pilotée n'est pas forcément celle de ce dépôt. ODICE_COMPOSE_DIR — ou
# l'option --dir — permet de viser une installation existante, typiquement un
# clone de zammad-docker-compose. Les données ne bougent alors pas d'un octet :
# ce sont les mêmes volumes, la même base.
COMPOSE_DIR="${ODICE_COMPOSE_DIR:-${REPO_ROOT}}"
for _i in "$@"; do
  [ "${_prev:-}" = '--dir' ] && COMPOSE_DIR="${_i}"
  _prev="${_i}"
done
COMPOSE_DIR="$(cd "${COMPOSE_DIR}" 2>/dev/null && pwd)" || {
  echo "Erreur : répertoire de pile introuvable : ${ODICE_COMPOSE_DIR:-${REPO_ROOT}}" >&2; exit 1; }

ENV_FILE="${COMPOSE_DIR}/.env"
STATE_FILE="${COMPOSE_DIR}/.odice-cutover-state"

cd "${COMPOSE_DIR}"
[ -f "${ENV_FILE}" ] || { echo "Erreur : .env absent dans ${COMPOSE_DIR}." >&2; exit 1; }

# Le nom des variables d'image diffère selon la pile : zammad-docker-compose
# utilise IMAGE_REPO/VERSION, la pile de ce dépôt ODICE_IMAGE_REPO/ODICE_IMAGE_TAG.
# On le déduit du compose plutôt que de le demander.
#
# Le motif cherche « ${IMAGE_REPO » et non « IMAGE_REPO » : ce dernier est une
# sous-chaîne d'ODICE_IMAGE_REPO, et la pile de ce dépôt était donc reconnue à
# tort comme un zammad-docker-compose. Les scripts y écrivaient alors IMAGE_REPO
# et VERSION — deux variables que son compose n'utilise pas — puis annonçaient
# un succès sans que l'image ait changé.
if grep -q '${IMAGE_REPO' "${COMPOSE_DIR}/docker-compose.yml" 2>/dev/null; then
  VAR_REPO='IMAGE_REPO'; VAR_TAG='VERSION'; PILE='zammad-docker-compose'
else
  VAR_REPO='ODICE_IMAGE_REPO'; VAR_TAG='ODICE_IMAGE_TAG'; PILE='odice-ticketing'
fi

# Le .env n'est PAS un script shell : Docker Compose y autorise des valeurs non
# quotées contenant des espaces (ODICE_PRODUCT_NAME=Odice Helpdesk), qu'un
# `source` prendrait pour une commande. On le lit sans jamais l'exécuter.
function env_get {
  local key="$1" default="${2:-}" value
  value="$(grep -E "^[[:space:]]*${key}=" "${ENV_FILE}" | tail -n1 | cut -d= -f2-)"
  value="${value%\"}"; value="${value#\"}"
  value="${value%\'}"; value="${value#\'}"
  printf '%s' "${value:-${default}}"
}

function env_set {
  local key="$1" value="$2"
  if grep -qE "^[[:space:]]*${key}=" "${ENV_FILE}"; then
    # Séparateur « | » : évite d'échapper les « / » des tags et des chemins.
    sed -i.bak -E "s|^[[:space:]]*${key}=.*|${key}=${value}|" "${ENV_FILE}"
    rm -f "${ENV_FILE}.bak"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${ENV_FILE}"
  fi
}

function dc { docker compose --env-file "${ENV_FILE}" "$@"; }

# Lit une variable dans le .env d'une AUTRE pile que celle qu'on pilote.
# Indispensable aux garde-fous : comparer deux environnements suppose de lire
# chez les deux, sans se déplacer ni changer d'ENV_FILE.
function env_get_at {
  local dir="$1" key="$2" default="${3:-}" value
  [ -f "${dir}/.env" ] || { printf '%s' "${default}"; return; }
  value="$(grep -E "^[[:space:]]*${key}=" "${dir}/.env" | tail -n1 | cut -d= -f2-)"
  value="${value%\"}"; value="${value#\"}"
  value="${value%\'}"; value="${value#\'}"
  printf '%s' "${value:-${default}}"
}

# Le nom de projet RÉELLEMENT résolu par Compose, et non celui qu'on suppose.
# Il dépend de COMPOSE_PROJECT_NAME, d'un `name:` dans le compose, ou à défaut
# du nom du répertoire — trois sources qu'on ne peut pas deviner de l'extérieur.
# C'est lui qui préfixe les volumes : deux piles qui le partageraient
# partageraient leurs données.
function project_name {
  local dir="${1:-${COMPOSE_DIR}}"
  (cd "${dir}" && docker compose --env-file "${dir}/.env" config --format json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])' 2>/dev/null) || printf ''
}

# Refuse d'agir si la pile visée n'est pas l'environnement attendu.
#
# L'environnement est une propriété de l'EMPLACEMENT, jamais un argument : une
# commande dangereuse doit le lire dans sa cible, pas le recevoir de l'appelant.
# Un `--dir` mal tapé ne doit pas pouvoir devenir une opération sur la
# production.
function require_environment {
  local expected="$1" dir="${2:-${COMPOSE_DIR}}" actual
  actual="$(env_get_at "${dir}" ODICE_ENVIRONMENT)"

  if [ "${actual}" != "${expected}" ]; then
    cat >&2 <<FAIL
Erreur : environnement inattendu.

  Répertoire visé : ${dir}
  Attendu         : ODICE_ENVIRONMENT=${expected}
  Trouvé          : ${actual:-<non renseigné>}

Posez ODICE_ENVIRONMENT dans le .env de cette pile, ou corrigez --dir.
FAIL
    exit 1
  fi
}

# URL de contrôle de santé. NGINX_PORT est le port INTERNE du conteneur nginx ;
# s'en servir comme port hôte ne marche que si la pile le publie tel quel, ce
# qui n'est le cas que de la production. Une pile qui publie ailleurs — ou sur
# la boucle locale seulement — renseigne ODICE_HEALTH_URL.
HEALTH_URL="$(env_get ODICE_HEALTH_URL "http://127.0.0.1:$(env_get NGINX_PORT 8080)/api/v1/getting_started")"

PG_USER="$(env_get POSTGRESQL_USER "$(env_get POSTGRES_USER zammad)")"
PG_DB="$(env_get POSTGRESQL_DB "$(env_get POSTGRES_DB zammad_production)")"
ROLLBACK_DIR="$(env_get ODICE_ROLLBACK_DIR "${REPO_ROOT}/tmp/rollback")"

# Vérifie que le répertoire de sauvegarde est utilisable AVANT d'engager quoi
# que ce soit. Sans ce contrôle, l'échec survient après la confirmation, une
# fois PostgreSQL démarré — au moment précis où l'on croit l'opération lancée.
function ensure_rollback_dir {
  if ! mkdir -p "${ROLLBACK_DIR}" 2>/dev/null; then
    cat >&2 <<FAIL
Erreur : impossible de créer ${ROLLBACK_DIR}.

  sudo mkdir -p ${ROLLBACK_DIR} && sudo chown "\$USER" ${ROLLBACK_DIR}
FAIL
    return 1
  fi
  if ! touch "${ROLLBACK_DIR}/.odice-write-test" 2>/dev/null; then
    cat >&2 <<FAIL
Erreur : ${ROLLBACK_DIR} n'est pas accessible en écriture pour $(id -un).

  sudo chown "\$USER" ${ROLLBACK_DIR}

C'est là que sera écrite la sauvegarde d'avant migration — celle qui rend le
retour arrière possible. On ne va pas plus loin sans elle.
FAIL
    return 1
  fi
  rm -f "${ROLLBACK_DIR}/.odice-write-test"
  echo "  sauvegardes  : ${ROLLBACK_DIR} (accessible en écriture)"
}

# Dump de la base en cours, conservé hors des volumes Docker. C'est lui, et lui
# seul, qui rend le retour arrière possible : les migrations Odice ajoutent des
# contraintes que le code historique ne respecte pas, elles ne se défont pas.
function dump_database {
  local label="$1" target
  mkdir -p "${ROLLBACK_DIR}"
  target="${ROLLBACK_DIR}/$(date -u +%Y%m%d%H%M%S)_${label}.psql.gz"
  echo "  sauvegarde → ${target}"
  dc exec -T zammad-postgresql \
    pg_dump --no-owner --no-privileges -U "${PG_USER}" -d "${PG_DB}" | gzip > "${target}"
  gzip -t "${target}" || { echo "  sauvegarde CORROMPUE, on s'arrête." >&2; return 1; }
  echo "  $(du -h "${target}" | cut -f1) — intègre"
  printf '%s' "${target}"
}

function restore_database {
  local dump="$1"
  [ -f "${dump}" ] || { echo "Erreur : ${dump} introuvable." >&2; return 1; }
  gzip -t "${dump}" || { echo "Erreur : ${dump} est corrompu." >&2; return 1; }
  echo "  restauration de ${dump}"
  dc exec -T zammad-postgresql \
    psql -v ON_ERROR_STOP=1 -q -U "${PG_USER}" -d "${PG_DB}" \
    -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'
  gunzip -c "${dump}" | dc exec -T zammad-postgresql \
    psql -v ON_ERROR_STOP=1 -q -U "${PG_USER}" -d "${PG_DB}"
}

function wait_for_postgres {
  echo '  attente de PostgreSQL…'
  until dc exec -T zammad-postgresql pg_isready -q -U "${PG_USER}"; do sleep 2; done
}

# 200 comme 403 prouvent que Zammad répond : /api/v1/getting_started renvoie 403
# dès que le système est configuré.
function wait_for_http {
  local url="$1" limit="${2:-300}" deadline code
  deadline=$(( $(date +%s) + limit ))
  echo "  attente de ${url}…"
  while :; do
    code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "${url}" 2>/dev/null || true)"
    case "${code}" in 200|403) echo "  → HTTP ${code}"; return 0 ;; esac
    [ "$(date +%s)" -ge "${deadline}" ] && { echo "  aucune réponse (dernier code : ${code:-néant})" >&2; return 1; }
    sleep 5
  done
}

function confirm {
  local answer
  read -r -p "  $1 " answer
  [ "${answer}" = 'oui' ] || { echo 'Annulé.'; exit 1; }
}
