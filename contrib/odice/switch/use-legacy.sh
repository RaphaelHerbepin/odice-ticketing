#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — remet la version historique de Zammad en service.
#
# POURQUOI CE N'EST PAS QU'UN CHANGEMENT DE TAG. Les deux versions partagent la
# même base, et les migrations Odice ajoutent des contraintes que le code
# historique ne respecte pas :
#
#   - 20260724130000 pose un index UNIQUE sur `recent_views`, là où l'ancien
#     code fait un `RecentView.create!` sans protection → RecordNotUnique, soit
#     une erreur 500 à la deuxième ouverture d'un même ticket par un agent ;
#   - 20260707120000 passe `edited_at` en NOT NULL sans défaut → toute création
#     de traduction dans la base de connaissances échoue.
#
# Démarrer l'image historique sur la base migrée donnerait donc une application
# qui semble fonctionner puis casse sur le geste le plus courant. Ce script
# restaure la sauvegarde prise avant la bascule, ce qui remet le schéma dans
# l'état que cette image sait servir.
#
# Usage :
#   contrib/odice/switch/use-legacy.sh              # avec confirmation
#   contrib/odice/switch/use-legacy.sh --dry-run    # répétition à blanc
#   contrib/odice/switch/use-legacy.sh --dump <fichier.psql.gz>

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=contrib/odice/switch/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DRY_RUN=false
DUMP_OVERRIDE=''
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --dump)    DUMP_OVERRIDE="$2"; shift 2 ;;
    *)         echo "Option inconnue : $1" >&2; exit 1 ;;
  esac
done

LEGACY_REPO="$(env_get ODICE_LEGACY_IMAGE_REPO zammad/zammad)"
LEGACY_TAG="$(env_get ODICE_LEGACY_IMAGE_TAG)"
SITE="$(env_get ODICE_SITE_ADDRESS)"

echo '== État'
if [ -f "${STATE_FILE}" ]; then
  CUTOVER_AT="$(head -n1 "${STATE_FILE}")"
  DUMP="${DUMP_OVERRIDE:-$(grep '^pre_odice_dump=' "${STATE_FILE}" | cut -d= -f2- || true)}"
  echo "  bascule effectuée le ${CUTOVER_AT}"
else
  CUTOVER_AT=''
  DUMP="${DUMP_OVERRIDE:-$(find "${ROLLBACK_DIR}" -name '*_pre-odice.psql.gz' 2>/dev/null | sort | tail -n1 || true)}"
  echo '  aucune bascule enregistrée'
fi
echo "  image historique : ${LEGACY_REPO}:${LEGACY_TAG:-(non épinglée !)}"
echo "  sauvegarde       : ${DUMP:-AUCUNE}"

[ -n "${LEGACY_TAG}" ] || {
  echo >&2
  echo "Erreur : ODICE_LEGACY_IMAGE_TAG n'est pas renseigné dans .env." >&2
  echo "         Sans lui, impossible de savoir quelle version restaurer." >&2
  exit 1
}
[ -n "${DUMP}" ] && [ -f "${DUMP}" ] || {
  echo >&2
  echo "Erreur : aucune sauvegarde d'avant bascule trouvée." >&2
  echo "         Sans elle, démarrer l'image historique sur la base migrée" >&2
  echo "         produirait des erreurs 500 à l'ouverture des tickets." >&2
  echo "         Indiquez-en une avec --dump <fichier.psql.gz>." >&2
  exit 1
}

# Chiffrer la perte AVANT d'agir : c'est la seule information qui permette de
# décider en connaissance de cause.
if [ -n "${CUTOVER_AT}" ]; then
  echo
  echo '== Données créées depuis la bascule (elles seront PERDUES)'
  dc run --rm --no-deps zammad-railsserver bundle exec rails r "
    t = Time.zone.parse('${CUTOVER_AT}')
    tickets = Ticket.where('created_at > ?', t)
    puts \"  tickets  : #{tickets.count}\"
    tickets.order(:id).each { |x| puts \"    ##{x.number}  #{x.title}\" }
    puts \"  articles : #{Ticket::Article.where('created_at > ?', t).count}\"
    puts \"  comptes  : #{User.where('created_at > ?', t).count}\"
  " 2>/dev/null | grep -v '^[IWD], \[' || echo '  (pile injoignable — impossible de chiffrer)'
fi

if [ "${DRY_RUN}" = true ]; then
  echo
  echo 'Répétition à blanc : rien n a été modifié.'
  exit 0
fi

echo
confirm 'Taper « oui » pour revenir à la version historique :'

echo
echo '== 1/4 — Sauvegarde de l état Odice, avant de l écraser'
dc up -d zammad-postgresql
wait_for_postgres
dump_database odice-avant-retour >/dev/null

echo
echo '== 2/4 — Arrêt de la version Odice'
dc stop
dc up -d zammad-postgresql
wait_for_postgres

echo
echo '== 3/4 — Restauration du schéma d avant migration'
restore_database "${DUMP}"

echo
echo '== 4/4 — Démarrage de la version historique'
dc down
env_set ODICE_IMAGE_REPO "${LEGACY_REPO}"
env_set ODICE_IMAGE_TAG "${LEGACY_TAG}"
# Profil vidé : la tâche odice:provision n'existe pas dans l'image historique,
# son conteneur échouerait.
env_set COMPOSE_PROFILES ''
dc up -d

wait_for_http "http://127.0.0.1:$(env_get NGINX_PORT 8080)/api/v1/getting_started" 600 || {
  echo 'La version historique ne répond pas. Journaux :' >&2
  dc logs --tail 40 zammad-init zammad-railsserver >&2
  exit 1
}
wait_for_http "${SITE}/api/v1/getting_started" 120 || true

mv "${STATE_FILE}" "${STATE_FILE}.rolled-back-$(date -u +%Y%m%d%H%M%S)" 2>/dev/null || true

cat <<DONE

== En service : ${LEGACY_REPO}:${LEGACY_TAG}

  ${SITE}

  L état Odice a été sauvegardé dans ${ROLLBACK_DIR} avant d être écrasé : les
  données créées pendant la période Odice n y sont pas perdues, elles sont
  simplement hors ligne. Ressaisissez au besoin les tickets listés plus haut.

  Pour repartir vers Odice une fois le problème corrigé :
    make use-odice
DONE
