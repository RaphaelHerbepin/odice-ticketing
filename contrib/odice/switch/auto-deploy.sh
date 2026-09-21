#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — déploiement automatique : récupère la branche suivie et, si elle a
# avancé, met la pile à jour. Conçu pour être appelé par cron ou un minuteur
# systemd, donc SILENCIEUX quand il n'y a rien à faire.
#
# Ce que ce script ne fait pas, délibérément :
#   - il ne déploie jamais une image absente du registry. Un build prend 6 à 7
#     minutes ; tant qu'elle n'est pas là, il repart sans rien toucher et
#     réessaiera au passage suivant ;
#   - il ne déploie pas un commit dont le message porte [no-deploy] ;
#   - il ne s'exécute jamais deux fois en parallèle (verrou).
#
# Usage :
#   contrib/odice/switch/auto-deploy.sh                    # silencieux si rien à faire
#   contrib/odice/switch/auto-deploy.sh --verbose          # trace chaque étape
#   contrib/odice/switch/auto-deploy.sh --dir /opt/zammad-docker-compose

set -o errexit
set -o nounset
set -o pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SELF_DIR}/../../.." && pwd)"
BRANCH="${ODICE_DEPLOY_BRANCH:-odice/main}"
LOCK="${REPO}/.odice-auto-deploy.lock"
LOG="${ODICE_DEPLOY_LOG:-${REPO}/tmp/auto-deploy.log}"

VERBOSE=false
PASS_THROUGH=()
while [ $# -gt 0 ]; do
  case "$1" in
    --verbose) VERBOSE=true; shift ;;
    --dir)     PASS_THROUGH+=(--dir "$2"); shift 2 ;;
    *)         echo "Option inconnue : $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$(dirname "${LOG}")"

function say {
  # Toujours journalisé ; affiché seulement en mode bavard, pour qu'un cron
  # silencieux le reste tant qu'il n'y a rien à signaler.
  printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$1" >> "${LOG}"
  [ "${VERBOSE}" = true ] && echo "$1"
  return 0
}

# Verrou : un déploiement dure plusieurs minutes, le minuteur peut retomber
# dessus. `flock` est absent de macOS mais présent sur toute Debian.
if command -v flock >/dev/null 2>&1; then
  exec 9>"${LOCK}"
  flock -n 9 || { say 'déjà en cours, on passe'; exit 0; }
fi

cd "${REPO}"

if [ -n "$(git status --porcelain)" ]; then
  say 'ARRÊT : le dépôt a des modifications non commitées, rien ne sera déployé'
  exit 1
fi

git fetch --quiet origin "${BRANCH}"
LOCAL="$(git rev-parse HEAD)"
REMOTE="$(git rev-parse "origin/${BRANCH}")"

if [ "${LOCAL}" = "${REMOTE}" ]; then
  say "à jour (${LOCAL:0:8})"
  exit 0
fi

SUBJECT="$(git log -1 --format='%s' "${REMOTE}")"
if printf '%s' "${SUBJECT}" | grep -qF '[no-deploy]'; then
  say "commit ${REMOTE:0:8} marqué [no-deploy] : ignoré"
  git merge --ff-only "origin/${BRANCH}" --quiet
  exit 0
fi

say "nouveau commit ${REMOTE:0:8} — ${SUBJECT}"
git merge --ff-only "origin/${BRANCH}" --quiet

# deploy.sh refuse si l'image n'est pas publiée. Au premier passage suivant un
# push, c'est le cas normal : le build tourne encore. On revient à l'état
# précédent pour retenter à l'identique au prochain passage, plutôt que de
# laisser le dépôt en avance sur ce qui est déployé.
if ! "${SELF_DIR}/deploy.sh" "${PASS_THROUGH[@]+"${PASS_THROUGH[@]}"}" >> "${LOG}" 2>&1; then
  say "image pas encore publiée pour ${REMOTE:0:8} (ou échec) — nouvelle tentative au prochain passage"
  git reset --hard --quiet "${LOCAL}"
  exit 0
fi

say "déployé : ${REMOTE:0:8}"
