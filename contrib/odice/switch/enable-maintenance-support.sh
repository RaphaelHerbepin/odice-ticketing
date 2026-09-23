#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — rend une pile existante compatible avec la page de maintenance.
#
# La page de maintenance repose sur le fait de pouvoir retirer l'application des
# vhosts de nginx-proxy en vidant une variable du `.env` — le seul état qui
# survive à une recréation de conteneur. Cela suppose que `VIRTUAL_HOST` soit
# INTERPOLÉ dans le fichier compose, et non écrit en dur.
#
# Ce script fait la conversion, et refuse de la faire si elle ne se vérifie pas.
#
# L'ordre est celui qui compte : la variable est écrite dans le `.env` AVANT que
# le compose ne cesse de porter la valeur en dur. L'inverse laisserait, entre
# les deux écritures, une configuration sans vhost — et un `up -d` malencontreux
# à cet instant rendrait le site invisible.
#
# AUCUN conteneur n'est redémarré ici : la conversion ne prend effet qu'au
# prochain `docker compose up -d`, et `docker compose config` permet de vérifier
# entre-temps que rien n'a changé.
#
# Usage :
#   contrib/odice/switch/enable-maintenance-support.sh --dir /opt/zammad-docker-compose

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=contrib/odice/switch/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh" "$@"

OVERRIDE="${COMPOSE_DIR}/docker-compose.override.yml"

echo "== Compatibilité avec la page de maintenance : ${COMPOSE_DIR}"

# La valeur telle que Compose la résout AUJOURD'HUI, pour le service nginx et
# lui seul. C'est la référence : tout ce qui suit doit la laisser inchangée.
#
# Lue en JSON, et non par un `grep` sur la sortie texte : l'ancre du compose
# amont déclare `VIRTUAL_HOST:` sur TOUS les services zammad, qui se résolvent
# donc en `null`. Un `grep | head -1` attrape l'un de ces null — c'est ce que
# faisait la première version de ce script, qui écrivait « null » dans le .env
# en annonçant un succès.
function resolved_virtual_host {
  (cd "${COMPOSE_DIR}" && docker compose --env-file "${ENV_FILE}" config --format json 2>/dev/null \
    | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
value = (d.get("services", {}).get("zammad-nginx", {}).get("environment", {}) or {}).get("VIRTUAL_HOST")
print(value if value else "")
') || printf ''
}

BEFORE="$(resolved_virtual_host)"
if [ -z "${BEFORE}" ]; then
  cat >&2 <<FAIL
Erreur : aucun VIRTUAL_HOST résolu dans cette pile.

Elle n'est pas exposée par nginx-proxy, ou l'override n'est pas là où on le
cherche. Rien n'a été modifié.
FAIL
  exit 1
fi
echo "   vhost actuellement résolu : ${BEFORE}"

if [ "$(env_get ZAMMAD_VIRTUAL_HOST)" = "${BEFORE}" ] \
   && grep -q 'VIRTUAL_HOST: *\${ZAMMAD_VIRTUAL_HOST' "${OVERRIDE}" 2>/dev/null; then
  echo "   déjà compatible, rien à faire."
  exit 0
fi

[ -f "${OVERRIDE}" ] || { echo "Erreur : ${OVERRIDE} introuvable." >&2; exit 1; }

# 1. La variable d'abord. Si le script s'arrête après cette ligne, la pile
#    fonctionne exactement comme avant — la variable est simplement inutilisée.
env_set ZAMMAD_VIRTUAL_HOST "${BEFORE}"
echo "   ZAMMAD_VIRTUAL_HOST=${BEFORE} écrit dans ${ENV_FILE}"

# 2. L'indirection ensuite, sur une copie.
BACKUP="${OVERRIDE}.avant-maintenance-$(date -u +'%Y%m%dT%H%M%SZ')"
cp "${OVERRIDE}" "${BACKUP}"
sed -i.tmp -E "s|^([[:space:]]*)VIRTUAL_HOST:[[:space:]]*[\"']?${BEFORE}[\"']?[[:space:]]*\$|\\1VIRTUAL_HOST: \\\${ZAMMAD_VIRTUAL_HOST:-}|" "${OVERRIDE}"
rm -f "${OVERRIDE}.tmp"

# 3. La substitution a-t-elle seulement eu lieu ?
#
#    Vérifier que Compose résout toujours la même valeur ne suffit PAS : si le
#    `sed` n'a rien remplacé, la valeur en dur est toujours là et se résout
#    évidemment à l'identique. Le script annoncerait alors un succès, et la
#    page de maintenance ne fonctionnerait pas le jour où l'on en aurait besoin.
if ! grep -q 'VIRTUAL_HOST: *\${ZAMMAD_VIRTUAL_HOST' "${OVERRIDE}"; then
  cp "${BACKUP}" "${OVERRIDE}"
  cat >&2 <<FAIL

ÉCHEC : la ligne VIRTUAL_HOST n'a pas pu être convertie automatiquement.

Elle n'a pas la forme attendue — guillemets, commentaire en fin de ligne, ou
valeur écrite autrement. L'override a été RESTAURÉ, aucun conteneur n'a été
touché, le site est intact.

À convertir à la main dans ${OVERRIDE} :

    VIRTUAL_HOST: \${ZAMMAD_VIRTUAL_HOST:-}

ZAMMAD_VIRTUAL_HOST=${BEFORE} est déjà en place dans ${ENV_FILE}.
FAIL
  exit 1
fi

# 4. Et l'on vérifie que Compose résout TOUJOURS la même chose. C'est ce
#    contrôle qui distingue une conversion sûre d'un site rendu invisible.
AFTER="$(resolved_virtual_host)"
if [ "${AFTER}" != "${BEFORE}" ]; then
  cp "${BACKUP}" "${OVERRIDE}"
  cat >&2 <<FAIL

ÉCHEC : après conversion, Compose résout « ${AFTER:-<vide>} » au lieu de « ${BEFORE} ».

L'override a été RESTAURÉ depuis ${BACKUP}. Aucun conteneur n'a été touché, le
site est intact. La ligne VIRTUAL_HOST de ${OVERRIDE} n'a probablement pas la
forme attendue ; à convertir à la main en :

    VIRTUAL_HOST: \${ZAMMAD_VIRTUAL_HOST:-}
FAIL
  exit 1
fi

cat <<DONE
   vhost résolu après conversion : ${AFTER}  (inchangé)
   sauvegarde de l'ancien fichier : ${BACKUP}

Conversion faite, et vérifiée. Aucun conteneur n'a été redémarré : la pile
tourne encore sur l'ancienne configuration, strictement équivalente.

Pour l'appliquer, au moment qui vous convient :

  cd ${COMPOSE_DIR} && docker compose up -d zammad-nginx

La page de maintenance sera alors utilisable :

  make maintenance-status ZDC=${COMPOSE_DIR}
DONE
