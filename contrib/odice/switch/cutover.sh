#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — bascule de la pile historique vers la pile Odice.
#
# POINT DE NON-RETOUR. Tout ce qui précède ce script s'annule sans laisser de
# trace. À partir du moment où la pile historique est arrêtée et où les agents
# écrivent dans Odice, revenir en arrière coûte les données créées entre-temps
# (rollback.sh les chiffre et les liste).
#
# Ce que fait le script, dans cet ordre :
#   1. contrôles préalables, puis confirmation explicite ;
#   2. arrêt de la pile historique — sa base est GELÉE ici, c'est le filet ;
#   3. dump frais et restauration dans la pile Odice, SANS neutralisation ;
#   4. application de la configuration Odice avec le domaine canonique ;
#   5. réindexation Elasticsearch ;
#   6. bascule de l'amont Caddy, en quelques secondes ;
#   7. horodatage du point de non-retour.
#
# Usage : contrib/odice/switch/cutover.sh

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=contrib/odice/switch/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SITE="$(env_get ODICE_SITE_ADDRESS)"
SITE_HOST="${SITE#*://}"
FQDN="$(env_get ZAMMAD_FQDN "${SITE_HOST}")"
HTTP_TYPE="$(env_get ZAMMAD_HTTP_TYPE https)"
LEGACY_UPSTREAM="$(env_get ODICE_LEGACY_UPSTREAM host.docker.internal:8080)"
EXPORT_DIR="${REPO_ROOT}/tmp/cutover"

if [ -f "${STATE_FILE}" ]; then
  echo "Une bascule a déjà eu lieu le $(head -n1 "${STATE_FILE}")." >&2
  echo "Supprimez ${STATE_FILE} pour en refaire une." >&2
  exit 1
fi

echo '== Contrôles préalables'
[ -n "${SITE}" ] || { echo "Erreur : ODICE_SITE_ADDRESS non renseigné dans .env." >&2; exit 1; }
legacy_compose ps --services >/dev/null || exit 1
echo "  pile historique : $(legacy_compose ps --services | wc -l | tr -d ' ') services déclarés"
odice_compose ps --services >/dev/null
echo "  pile Odice      : accessible"
echo "  domaine         : ${SITE}"

cat <<WARN

  ┌──────────────────────────────────────────────────────────────────────────┐
  │  POINT DE NON-RETOUR                                                     │
  │                                                                          │
  │  La pile historique va être ARRÊTÉE et ${SITE_HOST}
  │  va être servi par la pile Odice.                                        │
  │                                                                          │
  │  Sa base reste intacte : le retour arrière prend 2 à 3 minutes, mais il  │
  │  perd tout ce qui aura été créé dans Odice entre-temps.                  │
  │                                                                          │
  │  Coupure attendue : 5 à 10 minutes.                                      │
  └──────────────────────────────────────────────────────────────────────────┘

WARN
confirm 'Taper « oui » pour lancer la bascule :'

echo
echo '== 1/6 — Arrêt de la pile historique'
legacy_compose stop
echo '  arrêtée. Sa base ne bougera plus : c est le point de restauration.'

echo
echo '== 2/6 — Export des données'
mkdir -p "${EXPORT_DIR}"
"${REPO_ROOT}/contrib/odice/vps-pull.sh" \
  --local --path "$(env_get ODICE_LEGACY_COMPOSE_PATH /opt/zammad-docker-compose)" \
  --out "${EXPORT_DIR}"

echo
echo '== 3/6 — Restauration dans la pile Odice'
# --keep-channels : c'est la PRODUCTION, pas une copie. Les canaux, les
# déclencheurs et les automatisations doivent rester actifs.
yes oui | "${REPO_ROOT}/contrib/odice/restore-local.sh" --from "${EXPORT_DIR}" --keep-channels

echo
echo '== 4/6 — Configuration Odice sur le domaine canonique'
odice_compose run --rm --no-deps \
  -v "${REPO_ROOT}/lib/tasks/odice:/opt/zammad/lib/tasks/odice:ro" \
  -e ODICE_PROVISION_FORCE=1 -e ZAMMAD_FQDN="${FQDN}" -e ZAMMAD_HTTP_TYPE="${HTTP_TYPE}" \
  zammad-railsserver bundle exec rake odice:provision

echo
echo '== 5/6 — Réindexation Elasticsearch'
# zammad-init ne reconstruit pas un index existant : celui de la phase de
# validation contient encore la copie, il faut donc le refaire explicitement.
if [ "$(env_get ELASTICSEARCH_ENABLED true)" = 'true' ]; then
  odice_compose run --rm --no-deps zammad-railsserver bundle exec rake zammad:searchindex:rebuild
else
  echo '  Elasticsearch désactivé, rien à faire.'
fi

echo
echo '== 6/6 — Bascule du domaine canonique'
odice_compose up -d
wait_for_http "http://127.0.0.1:$(env_get NGINX_PORT 8080)/api/v1/getting_started" 180 || {
  echo 'La pile Odice ne répond pas : bascule ANNULÉE, la pile historique peut être redémarrée.' >&2
  echo "  contrib/odice/switch/rollback.sh" >&2
  exit 1
}
point_front_to 'zammad-nginx:8080'

{
  date -u +'%Y-%m-%dT%H:%M:%SZ'
  echo "legacy_upstream=${LEGACY_UPSTREAM}"
} > "${STATE_FILE}"

echo
echo '== Terminé'
wait_for_http "${SITE}/api/v1/getting_started" 60 || true
cat <<DONE

  ${SITE} est désormais servi par la pile Odice.

  Contrôles à faire tout de suite :
    - connexion SSO d un agent
    - ouverture d un ticket ancien, avec pièce jointe
    - création d un ticket : les champs conditionnels apparaissent-ils ?
    - temps réel : une modification se propage-t-elle dans un autre onglet ?

  Retour arrière (2 à 3 min, perd les données créées depuis maintenant) :
    contrib/odice/switch/rollback.sh

  Fenêtre de décision conseillée : 48 heures. Au-delà, on corrige en avant.
DONE
