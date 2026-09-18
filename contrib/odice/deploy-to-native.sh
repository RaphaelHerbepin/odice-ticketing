#!/usr/bin/env bash
# Odice — déploiement de la personnalisation vers une instance Zammad NATIVE
# (installée par paquet .deb/.rpm, dans /opt/zammad).
#
# Pourquoi ce détour : une installation native ne peut pas recompiler le
# frontend Vue. `script/build/cleanup.sh` supprime `node_modules` du paquet
# (« only required during building »), et ni Node ni pnpm ne sont installés sur
# le serveur. On construit donc l'image Docker de ce dépôt — qui produit
# exactement la même arborescence /opt/zammad — et on en extrait les fichiers
# déjà compilés.
#
#   ./contrib/odice/deploy-to-native.sh utilisateur@serveur
#   ./contrib/odice/deploy-to-native.sh utilisateur@serveur --dry-run
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

CIBLE="${1:-}"
if [ -z "$CIBLE" ]; then
  echo "Usage : $0 <utilisateur@serveur> [--dry-run]" >&2
  exit 1
fi
DRY=""
[ "${2:-}" = "--dry-run" ] && DRY="--dry-run"

IMAGE="${ODICE_IMAGE_REPO:-odice-ticketing}:${ODICE_IMAGE_TAG:-develop}"
EXPORT_DIR="$(mktemp -d)"
trap 'rm -rf "$EXPORT_DIR"' EXIT

# Chemins à déployer. Les sources de app/frontend/ ne servent à rien ici :
# elles sont déjà compilées dans public/assets/frontend/vite.
CHEMINS=(
  # Résultat du build : c'est le cœur du rebranding (Sprockets + Vite + polices
  # + images de marque). 49 Mo environ.
  "public/assets"
  "public/favicon.ico"
  "public/apple-touch-icon.png"

  # Code serveur ajouté ou modifié.
  "app/services/service/ticket/statistics.rb"
  "app/graphql/gql/queries/ticket/statistics.rb"
  "app/graphql/gql/types/ticket/statistics_type.rb"
  "app/graphql/gql/types/ticket/statistics"
  "lib/tasks/odice/provision.rake"
  "app/controllers/mobile_controller.rb"
  "app/views/layouts/application.html.erb"
  "app/views/layouts/desktop.html.erb"
  "app/views/layouts/mobile.html.erb"
  "app/views/mailer/application.html.erb"

  # Sources de style, pour qu'un futur `rake assets:precompile` sur le serveur
  # reparte du bon pied (le legacy, lui, ne dépend que de Sprockets).
  "app/assets/stylesheets/custom"

  # Logo et scripts, utilisés par la tâche de provisionnement.
  "contrib/odice"
)

echo "1/4  Vérification de la version"
VERSION_IMAGE="$(docker run --rm --entrypoint cat "$IMAGE" /opt/zammad/VERSION | tr -d '\n')"
VERSION_CIBLE="$(ssh "$CIBLE" 'cat /opt/zammad/VERSION' 2>/dev/null | tr -d '\n' || echo 'inconnue')"
echo "     image  : $VERSION_IMAGE"
echo "     serveur: $VERSION_CIBLE"
if [ "${VERSION_IMAGE%%-*}" != "${VERSION_CIBLE%%-*}" ]; then
  echo
  echo "!! Les versions majeures diffèrent. Déployer des assets compilés d'une" >&2
  echo "   autre version que le code du serveur produit une instance incohérente." >&2
  echo "   Alignez d'abord les versions, puis relancez." >&2
  exit 1
fi

echo "2/4  Extraction depuis l'image"
CID="$(docker create "$IMAGE")"
trap 'docker rm -f "$CID" >/dev/null 2>&1; rm -rf "$EXPORT_DIR"' EXIT
for chemin in "${CHEMINS[@]}"; do
  mkdir -p "$EXPORT_DIR/$(dirname "$chemin")"
  docker cp "$CID:/opt/zammad/$chemin" "$EXPORT_DIR/$chemin" 2>/dev/null \
    || echo "     (absent de l'image, ignoré : $chemin)"
done
echo "     $(du -sh "$EXPORT_DIR" | cut -f1) à transférer"

echo "3/4  Transfert vers $CIBLE"
# --delete volontairement ABSENT : on ne supprime rien sur le serveur, on
# superpose. Les assets obsolètes seront nettoyés par le prochain paquet.
rsync -az --info=stats1 $DRY \
  --rsync-path='sudo rsync' \
  --chown=zammad:zammad \
  "$EXPORT_DIR"/ "$CIBLE:/opt/zammad/"

if [ -n "$DRY" ]; then
  echo
  echo "Essai à blanc terminé — rien n'a été écrit."
  exit 0
fi

echo "4/4  Application côté serveur"
ssh "$CIBLE" 'bash -s' <<'DISTANT'
set -euo pipefail
# Les réglages de marque vivent en base : la tâche les (ré)applique.
sudo zammad run rake odice:provision || echo "!! odice:provision a échoué, à relancer à la main"
sudo zammad config:set ODICE_LOCALE_DEFAULT=fr-fr 2>/dev/null || true
sudo systemctl restart zammad
echo "Zammad redémarré."
DISTANT

echo
echo "Terminé. Videz le cache de votre navigateur pour recharger les assets."
