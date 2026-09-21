#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — met la version Odice en service sur le domaine de production.
#
# Une seule pile tourne à la fois, sur la MÊME base : basculer revient à changer
# le tag de l'image et à redémarrer. Ce script fait en plus les deux choses
# qu'on oublie sous pression :
#
#   1. il SAUVEGARDE la base avant de laisser les migrations s'appliquer —
#      c'est le seul moyen de revenir en arrière, car les migrations Odice
#      ajoutent des contraintes que le code historique ne respecte pas
#      (index unique sur recent_views, edited_at NOT NULL) ;
#   2. il épingle le tag de l'image historique, pour que la cible du retour
#      arrière ne change pas sous vos pieds.
#
# Usage : contrib/odice/switch/use-odice.sh [--tag 7.2.x-abcd1234]

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=contrib/odice/switch/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

TAG_OVERRIDE=''
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG_OVERRIDE="$2"; shift 2 ;;
    --dir) shift 2 ;;   # consommé par common.sh
    *)     echo "Option inconnue : $1" >&2; exit 1 ;;
  esac
done

ODICE_REPO="${ODICE_IMAGE_REPO:-$(env_get ODICE_IMAGE_REPO)}"
ODICE_TAG="${TAG_OVERRIDE:-${ODICE_IMAGE_TAG:-$(env_get ODICE_IMAGE_TAG odice-main)}}"
SITE="$(env_get ODICE_SITE_ADDRESS "$(env_get ZAMMAD_HTTP_TYPE https)://$(env_get ZAMMAD_FQDN localhost)")"

echo '== Contrôles préalables'
echo "  pile        : ${PILE} (${COMPOSE_DIR})"
[ -n "${ODICE_REPO}" ] || {
  echo "Erreur : dépôt de l'image Odice inconnu." >&2
  echo "         Renseignez ODICE_IMAGE_REPO dans ${ENV_FILE}, ou exportez-le." >&2
  exit 1
}
echo "  image visée : ${ODICE_REPO}:${ODICE_TAG}"
if docker pull "${ODICE_REPO}:${ODICE_TAG}" >/dev/null 2>&1; then
  echo '  image tirée du registry'
elif docker image inspect "${ODICE_REPO}:${ODICE_TAG}" >/dev/null 2>&1; then
  # Cas d'une image construite sur place : rien à tirer, elle est déjà là.
  echo '  image déjà présente localement'
else
  cat >&2 <<FAIL
Erreur : image ${ODICE_REPO}:${ODICE_TAG} introuvable, ni au registry ni en local.

  - le workflow CI l'a-t-il publiée ?   gh run list --repo <compte>/odice-ticketing
  - le registry est-il privé ?          echo <token> | docker login ghcr.io -u <compte> --password-stdin
  - le tag est-il le bon ?              voir ODICE_IMAGE_TAG dans .env
FAIL
  exit 1
fi

# Relever l'image en service AVANT de la remplacer : c'est la cible du retour.
CURRENT_IMAGE="$(dc ps --format '{{.Image}}' zammad-railsserver 2>/dev/null | head -n1 || true)"
[ -n "${CURRENT_IMAGE}" ] || CURRENT_IMAGE="$(env_get "${VAR_REPO}"):$(env_get "${VAR_TAG}")"
if [ -n "${CURRENT_IMAGE#:}" ] && [ "${CURRENT_IMAGE%:*}" != "${ODICE_REPO}" ]; then
  env_set ODICE_LEGACY_IMAGE_REPO "${CURRENT_IMAGE%:*}"
  env_set ODICE_LEGACY_IMAGE_TAG "${CURRENT_IMAGE##*:}"
  echo "  version historique épinglée : ${CURRENT_IMAGE}"
fi

cat <<WARN

  ┌────────────────────────────────────────────────────────────────────────┐
  │  Les migrations Odice vont s'appliquer à la base de PRODUCTION.        │
  │  Elles ne se défont pas : le retour arrière passe par la sauvegarde    │
  │  prise juste après cette confirmation.                                 │
  │                                                                        │
  │  Coupure attendue : 5 à 10 minutes.                                    │
  └────────────────────────────────────────────────────────────────────────┘

WARN
confirm 'Taper « oui » pour continuer :'

echo
echo '== 1/4 — Sauvegarde de la base, avant migration'
dc up -d zammad-postgresql
wait_for_postgres
DUMP="$(dump_database pre-odice)"

echo
echo '== 2/4 — Arrêt de la version en service'
# Sans -v : les volumes, donc la base, doivent survivre.
dc down

echo
echo '== 3/4 — Démarrage de la version Odice'
env_set "${VAR_REPO}" "${ODICE_REPO}"
env_set "${VAR_TAG}" "${ODICE_TAG}"
# Le profil `odice` ajoute odice-provision, dont la tâche rake n'existe que dans
# cette image. On l'inscrit dans .env plutôt que de le passer à la volée : ainsi
# `make up`, `make restart` et tout appel direct à docker compose restent
# corrects après la bascule, sans avoir à y penser.
if [ "${PILE}" = 'odice-ticketing' ]; then
  env_set COMPOSE_PROFILES odice
fi
dc up -d

echo
echo '== 4/4 — Contrôles'
if [ "${PILE}" != 'odice-ticketing' ]; then
  echo '  application de la configuration Odice…'
  dc exec -T zammad-railsserver bundle exec rake odice:provision || {
    echo '  (provisioning à rejouer plus tard : make provision)' >&2; }
fi

wait_for_http "http://127.0.0.1:$(env_get NGINX_PORT 8080)/api/v1/getting_started" 600 || {
  cat >&2 <<FAIL

  La version Odice ne répond pas. La base a été migrée, mais la sauvegarde
  d'avant migration est intacte :

    ${DUMP}

  Pour revenir en arrière :
    contrib/odice/switch/use-legacy.sh --dump ${DUMP}
FAIL
  exit 1
}

{
  date -u +'%Y-%m-%dT%H:%M:%SZ'
  echo "pre_odice_dump=${DUMP}"
  echo "legacy_image=$(env_get ODICE_LEGACY_IMAGE_REPO):$(env_get ODICE_LEGACY_IMAGE_TAG)"
} > "${STATE_FILE}"

wait_for_http "${SITE}/api/v1/getting_started" 120 || true

cat <<DONE

== En service : ${ODICE_REPO}:${ODICE_TAG}

  ${SITE}

  À vérifier tout de suite :
    - connexion d'un agent (SSO)
    - ouverture d'un ticket ancien, avec pièce jointe
    - création d'un ticket : les champs conditionnels apparaissent-ils ?
    - temps réel : une modification se propage-t-elle dans un autre onglet ?

  Retour arrière (environ 5 minutes) :
    make use-legacy

  Il restaure ${DUMP},
  donc tout ce qui aura été créé d'ici là sera perdu. use-legacy.sh le liste
  avant d'agir. Fenêtre de décision conseillée : 48 heures.
DONE
