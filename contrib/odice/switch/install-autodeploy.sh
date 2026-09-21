#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — installe (ou retire) le minuteur systemd du déploiement automatique.
#
# systemd plutôt que cron : le journal est consultable avec `journalctl`, l'état
# avec `systemctl status`, et `RandomizedDelaySec` évite que tous les serveurs
# d'un parc n'interrogent GitHub à la même seconde.
#
# Usage :
#   sudo contrib/odice/switch/install-autodeploy.sh /opt/zammad-docker-compose
#   sudo contrib/odice/switch/install-autodeploy.sh --remove

set -o errexit
set -o nounset
set -o pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
UNIT_DIR='/etc/systemd/system'
NAME='odice-auto-deploy'

if [ "${1:-}" = '--remove' ]; then
  systemctl disable --now "${NAME}.timer" 2>/dev/null || true
  rm -f "${UNIT_DIR}/${NAME}.timer" "${UNIT_DIR}/${NAME}.service"
  systemctl daemon-reload
  echo 'Déploiement automatique retiré.'
  exit 0
fi

ZDC="${1:?chemin de la pile Zammad attendu, par exemple /opt/zammad-docker-compose}"
[ -d "${ZDC}" ] || { echo "Erreur : ${ZDC} introuvable." >&2; exit 1; }
[ "$(id -u)" = '0' ] || { echo 'Erreur : à lancer avec sudo.' >&2; exit 1; }

# L'utilisateur propriétaire du dépôt : c'est lui qui a la clé SSH pour git et
# l'accès au démon Docker. Lancer le déploiement en root créerait des fichiers
# que cet utilisateur ne pourrait plus écrire.
OWNER="$(stat -c '%U' "${REPO}")"
echo "  dépôt      : ${REPO} (utilisateur ${OWNER})"
echo "  pile       : ${ZDC}"

cat > "${UNIT_DIR}/${NAME}.service" <<UNIT
[Unit]
Description=Odice — déploiement automatique depuis la branche suivie
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
User=${OWNER}
WorkingDirectory=${REPO}
ExecStart=${REPO}/contrib/odice/switch/auto-deploy.sh --dir ${ZDC}
# Un déploiement complet (sauvegarde, migrations, redémarrage) dépasse rarement
# quelques minutes ; au-delà, mieux vaut interrompre que laisser traîner.
TimeoutStartSec=1800
UNIT

cat > "${UNIT_DIR}/${NAME}.timer" <<UNIT
[Unit]
Description=Odice — vérifie toutes les 5 minutes si la branche a avancé

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
# Évite que le serveur n'interroge GitHub à la seconde près à chaque cycle.
RandomizedDelaySec=60
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now "${NAME}.timer"

cat <<DONE

Déploiement automatique actif.

  État        : systemctl status ${NAME}.timer
  Prochain    : systemctl list-timers ${NAME}.timer
  Journal     : journalctl -u ${NAME}.service -n 50
  Suivi fin   : tail -f ${REPO}/tmp/auto-deploy.log
  Suspendre   : sudo systemctl disable --now ${NAME}.timer
  Retirer     : sudo ${BASH_SOURCE[0]} --remove

Désormais, tout commit poussé sur la branche suivie part en production dès que
son image est construite. Pour en exclure un, mettez [no-deploy] dans son
message.
DONE
