#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — retour à la pile historique.
#
# Repose sur un principe simple : la base de la pile historique n'a pas été
# touchée depuis la bascule. On rallume, on repointe le domaine, c'est fini.
#
# CE QUE CELA COÛTE : tout ce qui a été créé dans Odice depuis la bascule reste
# dans la base Odice et n'apparaît pas dans la pile historique. Le script liste
# ces éléments avant de commuter, pour que rien ne soit perdu par inadvertance.
#
# INTERDIT ABSOLU, et c'est la raison d'être de ces deux piles séparées : ne
# jamais faire pointer l'image historique sur la base Odice migrée. Deux
# migrations ajoutent des contraintes que son code ne respecte pas —
# 20260724130000 pose un index unique sur `recent_views` là où l'ancien code
# fait un `create!` sans protection (erreur 500 à la deuxième ouverture d'un
# même ticket), et 20260707120000 passe `edited_at` en NOT NULL.
#
# Usage :
#   contrib/odice/switch/rollback.sh            # avec confirmation
#   contrib/odice/switch/rollback.sh --dry-run  # répétition à blanc

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=contrib/odice/switch/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DRY_RUN=false
[ "${1:-}" = '--dry-run' ] && DRY_RUN=true

SITE="$(env_get ODICE_SITE_ADDRESS)"
LEGACY_UPSTREAM="$(env_get ODICE_LEGACY_UPSTREAM host.docker.internal:8080)"

echo '== État'
if [ -f "${STATE_FILE}" ]; then
  CUTOVER_AT="$(head -n1 "${STATE_FILE}")"
  echo "  bascule effectuée le ${CUTOVER_AT}"
else
  CUTOVER_AT=''
  echo '  aucune bascule enregistrée — le domaine est peut-être déjà sur la pile historique.'
fi
echo "  amont actuel : $(env_get ODICE_PROD_UPSTREAM)"

# Chiffrer la perte AVANT de commuter : c'est la seule information qui permette
# de décider en connaissance de cause.
if [ -n "${CUTOVER_AT}" ]; then
  echo
  echo '== Données créées dans Odice depuis la bascule (elles ne suivront PAS)'
  odice_compose run --rm --no-deps zammad-railsserver bundle exec rails r "
    t = Time.zone.parse('${CUTOVER_AT}')
    tickets  = Ticket.where('created_at > ?', t)
    articles = Ticket::Article.where('created_at > ?', t)
    users    = User.where('created_at > ?', t)
    puts \"  tickets  : #{tickets.count}\"
    tickets.order(:id).each { |x| puts \"    ##{x.number}  #{x.title}\" }
    puts \"  articles : #{articles.count}\"
    puts \"  comptes  : #{users.count}\"
  " 2>/dev/null | grep -v '^[IWD], \[' || echo '  (pile Odice injoignable — impossible de chiffrer)'
fi

if [ "${DRY_RUN}" = true ]; then
  echo
  echo 'Répétition à blanc : rien n a été modifié.'
  exit 0
fi

echo
confirm 'Taper « oui » pour revenir à la pile historique :'

echo
echo '== 1/3 — Redémarrage de la pile historique'
legacy_compose start
wait_for_http "http://127.0.0.1:${LEGACY_UPSTREAM##*:}/api/v1/getting_started" 180 || {
  echo 'La pile historique ne répond pas : le domaine n a PAS été commuté.' >&2
  echo "  Inspectez : (cd $(env_get ODICE_LEGACY_COMPOSE_PATH) && docker compose logs --tail 50)" >&2
  exit 1
}

echo
echo '== 2/3 — Bascule du domaine canonique'
point_front_to "${LEGACY_UPSTREAM}"

echo
echo '== 3/3 — Contrôle'
wait_for_http "${SITE}/api/v1/getting_started" 60 || true
mv "${STATE_FILE}" "${STATE_FILE}.rolled-back-$(date -u +%Y%m%d%H%M%S)" 2>/dev/null || true

cat <<DONE

  ${SITE} est de nouveau servi par la pile historique.

  La pile Odice tourne toujours, avec ses données : rien n est perdu, mais elle
  n est plus exposée. Ressaisissez au besoin les éléments listés plus haut.

  Pour repartir vers Odice une fois le problème corrigé :
    contrib/odice/switch/cutover.sh
DONE
