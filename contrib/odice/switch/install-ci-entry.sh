#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — installe les points d'entrée de déploiement HORS du dépôt.
#
# Pourquoi hors du dépôt : le déploiement fait `git checkout --force` sur le
# dépôt. Bash lit un script au fil de son exécution ; réécrire sous lui le
# fichier qu'il est en train d'interpréter le fait poursuivre sur un contenu
# décalé. Les points d'entrée doivent donc vivre là où git ne les touche pas.
#
# En contrepartie : toute modification de ces deux fichiers exige de rejouer ce
# script sur le serveur. Sinon on débogue une version différente de celle qu'on
# lit dans le dépôt.
#
# Usage (sur le serveur, en root ou avec sudo) :
#   contrib/odice/switch/install-ci-entry.sh
set -o errexit -o nounset -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${ODICE_SBIN_DIR:-/usr/local/sbin}"

install -m 0755 "${HERE}/ci-deploy-staging.sh"    "${DEST}/odice-deploy-staging"
install -m 0755 "${HERE}/ci-deploy-production.sh" "${DEST}/odice-deploy-production"

cat <<DONE
Points d'entrée installés :

  ${DEST}/odice-deploy-staging
  ${DEST}/odice-deploy-production

Lignes à poser dans ~/.ssh/authorized_keys (une par clé) :

  command="${DEST}/odice-deploy-staging",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAA… odice-ci-staging
  command="${DEST}/odice-deploy-production",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAA… odice-ci-prod

Rappel : après toute modification de ci-deploy-*.sh dans le dépôt, rejouer ce
script — sans quoi le serveur continue d'exécuter l'ancienne version.
DONE
