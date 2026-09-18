# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — fonctions partagées par cutover.sh et rollback.sh.
# Ce fichier se source, il ne s'exécute pas.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
# Horodatage du point de non-retour : il sert au rollback pour chiffrer le delta
# de tickets créés depuis la bascule.
STATE_FILE="${REPO_ROOT}/.odice-cutover-state"

cd "${REPO_ROOT}"

# Le .env n'est PAS un script shell : Docker Compose y autorise des valeurs non
# quotées contenant des espaces. On le lit sans jamais l'exécuter.
function env_get {
  local key="$1" default="${2:-}" value
  value="$(grep -E "^[[:space:]]*${key}=" "${ENV_FILE}" 2>/dev/null | tail -n1 | cut -d= -f2-)"
  value="${value%\"}"; value="${value#\"}"
  value="${value%\'}"; value="${value#\'}"
  printf '%s' "${value:-${default}}"
}

# Réécrit une clé en place, ou l'ajoute si elle manque.
function env_set {
  local key="$1" value="$2"
  if grep -qE "^[[:space:]]*${key}=" "${ENV_FILE}"; then
    # Le séparateur « | » évite d'échapper les « / » des CIDR et des URL.
    sed -i.bak -E "s|^[[:space:]]*${key}=.*|${key}=${value}|" "${ENV_FILE}"
    rm -f "${ENV_FILE}.bak"
  else
    printf '\n%s=%s\n' "${key}" "${value}" >> "${ENV_FILE}"
  fi
}

function odice_compose { docker compose --env-file "${ENV_FILE}" "$@"; }

function legacy_compose {
  local path; path="$(env_get ODICE_LEGACY_COMPOSE_PATH /opt/zammad-docker-compose)"
  [ -d "${path}" ] || { echo "Erreur : pile historique introuvable dans ${path}." >&2
                        echo "         Renseignez ODICE_LEGACY_COMPOSE_PATH dans .env." >&2; return 1; }
  ( cd "${path}" && docker compose "$@" )
}

# Bascule l'amont du domaine canonique, puis recrée Caddy. C'est l'opération
# qui prend effet en quelques secondes, dans un sens comme dans l'autre.
function point_front_to {
  local upstream="$1"
  echo "  amont du domaine canonique → ${upstream}"
  env_set ODICE_PROD_UPSTREAM "${upstream}"
  COMPOSE_PROFILES=front odice_compose up -d --force-recreate odice-caddy
}

# Attend qu'une URL réponde, sans dépendre d'un `timeout` absent sur macOS.
function wait_for_http {
  local url="$1" limit="${2:-120}" deadline code
  deadline=$(( $(date +%s) + limit ))
  while :; do
    code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "${url}" 2>/dev/null || true)"
    # 200 comme 403 prouvent que Zammad répond : /api/v1/getting_started renvoie
    # 403 dès que le système est configuré.
    case "${code}" in 200|403) echo "  ${url} → HTTP ${code}"; return 0 ;; esac
    [ "$(date +%s)" -ge "${deadline}" ] && { echo "  ${url} ne répond pas (dernier code : ${code:-aucun})" >&2; return 1; }
    sleep 3
  done
}

function confirm {
  local answer
  read -r -p "  $1 " answer
  [ "${answer}" = 'oui' ] || { echo 'Annulé.'; exit 1; }
}
