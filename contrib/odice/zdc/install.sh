#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — installe le complément dans une installation zammad-docker-compose.
#
# Ce script N'ÉCRASE RIEN. `docker-compose.override.yml` est le point
# d'extension standard de Compose : beaucoup d'installations l'utilisent déjà —
# typiquement pour déclarer VIRTUAL_HOST et LETSENCRYPT_HOST à destination d'un
# nginx-proxy. L'écraser coupe le site sans le moindre message d'erreur, et la
# panne ne se voit qu'au navigateur. Le complément est donc déposé sous un nom
# qui lui est propre, et chaîné par COMPOSE_FILE.
#
# Usage : contrib/odice/zdc/install.sh /opt/zammad-docker-compose

set -o errexit
set -o nounset
set -o pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZDC="${1:?chemin du repertoire zammad-docker-compose attendu}"
ZDC="$(cd "${ZDC}" && pwd)"
TARGET="${ZDC}/docker-compose.odice.yml"
ENV_FILE="${ZDC}/.env"

[ -f "${ZDC}/docker-compose.yml" ] || {
  echo "Erreur : ${ZDC}/docker-compose.yml introuvable." >&2; exit 1; }

echo "== Installation du complément Odice dans ${ZDC}"

cp "${SRC_DIR}/docker-compose.override.yml" "${TARGET}"
echo "  déposé : docker-compose.odice.yml"

# Chaînage explicite. Dès que COMPOSE_FILE est défini, Compose ne charge plus
# docker-compose.override.yml automatiquement : il faut donc l'y remettre.
FILES='docker-compose.yml'
[ -f "${ZDC}/docker-compose.override.yml" ] && {
  FILES="${FILES}:docker-compose.override.yml"
  echo "  votre docker-compose.override.yml est CONSERVÉ et chaîné"
}
FILES="${FILES}:docker-compose.odice.yml"

# Le .env peut ne pas se terminer par un saut de ligne : sans cette précaution,
# la première ligne ajoutée se collerait à la dernière ligne existante.
[ -f "${ENV_FILE}" ] || touch "${ENV_FILE}"
[ -s "${ENV_FILE}" ] && [ -n "$(tail -c1 "${ENV_FILE}")" ] && printf '\n' >> "${ENV_FILE}"

# La chaîne est RECONSTRUITE à chaque exécution, et pas seulement complétée du
# maillon Odice.
#
# Un docker-compose.override.yml déposé APRÈS un premier passage de ce script
# n'était sinon jamais chaîné : le script voyait son propre complément déjà
# présent, annonçait « déjà présent », et l'override restait silencieusement
# ignoré par Compose. Un fichier de configuration sans effet et sans message
# est le pire des deux mondes.
if grep -qE '^[[:space:]]*COMPOSE_FILE=' "${ENV_FILE}"; then
  CURRENT="$(grep -E '^[[:space:]]*COMPOSE_FILE=' "${ENV_FILE}" | tail -n1 | cut -d= -f2-)"
  WANTED="${CURRENT}"

  # L'override de l'exploitant vient juste après le fichier de base, avant le
  # complément Odice : ce dernier doit pouvoir surcharger ce qu'il y trouve.
  if [ -f "${ZDC}/docker-compose.override.yml" ]; then
    case ":${WANTED}:" in
      *:docker-compose.override.yml:*) ;;
      *) WANTED="$(printf '%s' "${WANTED}" | sed 's|docker-compose\.yml|docker-compose.yml:docker-compose.override.yml|')"
         echo "  votre docker-compose.override.yml manquait dans la chaîne — ajouté" ;;
    esac
  fi

  case ":${WANTED}:" in
    *:docker-compose.odice.yml:*) ;;
    *) WANTED="${WANTED}:docker-compose.odice.yml" ;;
  esac

  if [ "${WANTED}" = "${CURRENT}" ]; then
    echo "  COMPOSE_FILE déjà complet"
  else
    sed -i.bak -E "s|^[[:space:]]*COMPOSE_FILE=.*|COMPOSE_FILE=${WANTED}|" "${ENV_FILE}"
    rm -f "${ENV_FILE}.bak"
    echo "  COMPOSE_FILE=${WANTED}"
  fi
else
  printf 'COMPOSE_FILE=%s\n' "${FILES}" >> "${ENV_FILE}"
  echo "  COMPOSE_FILE=${FILES}"
fi

if grep -q 'ODICE_IMAGE_REPO' "${ENV_FILE}" 2>/dev/null; then
  echo '  configuration Odice déjà présente dans .env'
else
  cat "${SRC_DIR}/env.odice.example" >> "${ENV_FILE}"
  echo '  configuration Odice ajoutée au .env'
fi

echo
echo '== Vérification — les fichiers réellement chargés'
( cd "${ZDC}" && docker compose config --no-interpolate >/dev/null 2>&1 \
  && echo '  la configuration se résout correctement' \
  || echo '  ATTENTION : docker compose config échoue, relisez COMPOSE_FILE' )

cat <<NEXT

Relisez ${ENV_FILE}, en particulier ODICE_IMAGE_TAG et ODICE_ROLLBACK_DIR.

Contrôlez que votre exposition publique est intacte AVANT de basculer :

  cd ${ZDC} && docker compose config | grep -E 'VIRTUAL_HOST|LETSENCRYPT'

Si ces variables n'apparaissent pas alors que vous utilisez nginx-proxy, ne
basculez pas : le site deviendrait injoignable.
NEXT
