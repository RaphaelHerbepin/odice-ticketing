#!/usr/bin/env bash
# Odice — construction de l'image applicative.
#
# Le Dockerfile exige `--build-arg COMMIT_SHA` (il sort en erreur sinon) et
# réécrit VERSION en « 7.2.x-<sha8>.docker ». Taguer l'image avec la même
# chaîne fait donc correspondre exactement le tag et la version affichée dans
# Administration → Version : on remonte d'un ticket de support au commit.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

PUSH=false
[[ "${1:-}" == "--push" ]] && PUSH=true

COMMIT_SHA="$(git rev-parse HEAD)"
SHORT_SHA="${COMMIT_SHA:0:8}"
ZAMMAD_VERSION="$(tr -d '\n' < VERSION)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
REPO="${ODICE_IMAGE_REPO:-odice-ticketing}"
PLATFORM="${ODICE_BUILD_PLATFORM:-}"

# Un arbre de travail modifié rendrait le tag mensonger : le Dockerfile tronque
# le SHA à 8 caractères, sans marqueur « dirty ».
if ! git diff-index --quiet HEAD --; then
  echo "!! Arbre de travail modifié : le tag ${SHORT_SHA} ne décrira pas exactement le contenu." >&2
  if $PUSH; then
    echo "   Publication refusée depuis un arbre modifié." >&2
    exit 1
  fi
fi

TAGS=(-t "${REPO}:${ZAMMAD_VERSION}-${SHORT_SHA}" -t "${REPO}:${BRANCH}")

echo "Construction ${REPO}:${ZAMMAD_VERSION}-${SHORT_SHA}"
# Construire pour linux/amd64 depuis un Mac via QEMU est déconseillé :
# assets:precompile fait tourner rolldown, un binaire natif Rust — comptez 30 à
# 60 minutes, avec des plantages possibles. Préférer GitHub Actions.
docker buildx build \
  ${PLATFORM:+--platform "$PLATFORM"} \
  --build-arg "COMMIT_SHA=${COMMIT_SHA}" \
  --pull \
  "${TAGS[@]}" \
  $($PUSH && echo --push || echo --load) \
  .
