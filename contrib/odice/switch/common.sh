# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — fonctions partagées par use-odice.sh et use-legacy.sh.
# Ce fichier se source, il ne s'exécute pas.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
STATE_FILE="${REPO_ROOT}/.odice-cutover-state"

cd "${REPO_ROOT}"
[ -f "${ENV_FILE}" ] || { echo "Erreur : .env absent à la racine du dépôt." >&2; exit 1; }

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

PG_USER="$(env_get POSTGRESQL_USER zammad)"
PG_DB="$(env_get POSTGRESQL_DB zammad_production)"
ROLLBACK_DIR="$(env_get ODICE_ROLLBACK_DIR "${REPO_ROOT}/tmp/rollback")"

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
