#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — extrait les données d'une instance Zammad tournant en Docker sur un
# serveur distant, et les écrit AU FORMAT ATTENDU par le conteneur
# `zammad-backup` de la pile Odice :
#
#   <horodatage>_zammad_db.psql.gz     ← contrib/docker/backup.sh:88
#   <horodatage>_zammad_files.tar.gz   ← contrib/docker/backup.sh:95
#
# Les deux noms sont imposés : la restauration les cherche par `find -name`.
#
# Le script ne dépend PAS du service de sauvegarde du serveur distant : il
# produit son propre `pg_dump`. Il fonctionne donc quelle que soit l'ancienneté
# du `docker-compose.yml` d'en face, et ne perturbe pas le cycle de sauvegarde
# en place. La production continue de tourner pendant l'opération.
#
# Usage :
#   contrib/odice/vps-pull.sh --host root@vps.odice.fr --path /opt/zammad-docker-compose --inspect
#   contrib/odice/vps-pull.sh --host root@vps.odice.fr --path /opt/zammad-docker-compose
#   contrib/odice/vps-pull.sh --host root@vps.odice.fr --path /opt/zammad --no-files
#
# Depuis le serveur lui-même (pendant la bascule), --local remplace SSH par une
# exécution directe — les commandes sont identiques :
#   contrib/odice/vps-pull.sh --local --path /opt/zammad-docker-compose

set -o errexit
set -o nounset
set -o pipefail

HOST=''
LOCAL=false
REMOTE_PATH=''
OUT_DIR='tmp/import'
INSPECT_ONLY=false
WITH_FILES=true
SVC_RAILS="${SVC_RAILS:-zammad-railsserver}"
SVC_PG="${SVC_PG:-zammad-postgresql}"

while [ $# -gt 0 ]; do
  case "$1" in
    --host)      HOST="$2"; shift 2 ;;
    --local)     LOCAL=true; shift ;;
    --path)      REMOTE_PATH="$2"; shift 2 ;;
    --out)       OUT_DIR="$2"; shift 2 ;;
    --inspect)   INSPECT_ONLY=true; shift ;;
    --no-files)  WITH_FILES=false; shift ;;
    -h|--help)   sed -n '3,22p' "$0"; exit 0 ;;
    *)           echo "Option inconnue : $1" >&2; exit 1 ;;
  esac
done

if { [ -z "${HOST}" ] && [ "${LOCAL}" = false ]; } || [ -z "${REMOTE_PATH}" ]; then
  cat >&2 <<'USAGE'
Erreur : --path est obligatoire, ainsi que --host ou --local.

  --host   utilisateur@serveur pour SSH, p. ex. root@vps.odice.fr
  --local  exécuter sur cette machine au lieu de passer par SSH
  --path   répertoire du docker-compose.yml,
           p. ex. /opt/zammad-docker-compose

Pour le retrouver sur le serveur :
  ssh <hôte> 'docker compose ls'
USAGE
  exit 1
fi

# `docker compose exec` SANS -T alloue un pseudo-terminal, qui réécrit les fins
# de ligne et corrompt silencieusement un flux gzip. Le -T n'est donc pas une
# coquetterie : sans lui, l'archive rapatriée ne se décompresse qu'à moitié.
function remote {
  if [ "${LOCAL}" = true ]; then
    bash -c "cd '${REMOTE_PATH}' && $1"
  else
    # shellcheck disable=SC2029  # l'expansion locale est voulue.
    ssh "${HOST}" "cd '${REMOTE_PATH}' && $1"
  fi
}

echo "== Instance : ${LOCAL:+locale }${HOST:+${HOST}:}${REMOTE_PATH}"
echo

echo "-- Services en cours d'exécution"
remote 'docker compose ps --format "  {{.Service}}\t{{.Status}}"' || {
  echo "Erreur : impossible de lire la pile Docker. Vérifiez --path." >&2
  exit 1
}
echo

echo "-- Version de Zammad"
remote "docker compose exec -T ${SVC_RAILS} cat /opt/zammad/VERSION"
echo

echo "-- Réglages structurants (quelques secondes, le temps de charger Rails)"
remote "docker compose exec -T ${SVC_RAILS} bundle exec rails r \
  \"%w[storage_provider fqdn http_type product_name es_url].each { |s| puts \\\"  #{s} = #{Setting.get(s)}\\\" }\""
echo

echo "-- Volumétrie"
remote "docker compose exec -T ${SVC_PG} sh -c \
  'psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -tAc \"SELECT pg_size_pretty(pg_database_size(current_database()))\"'"
remote "docker compose exec -T ${SVC_RAILS} du -sh /opt/zammad/storage 2>/dev/null || echo '  (pas de stockage fichier)'"
echo

if [ "${INSPECT_ONLY}" = true ]; then
  cat <<'HINT'
== Inspection terminée. Ce qu'il faut y lire :

  storage_provider = DB    → les pièces jointes sont dans la base : le dump
                             suffit, relancez avec --no-files.
  storage_provider = File  → elles sont sur le disque : l'archive de fichiers
                             est indispensable.

  La version doit être celle de la pile Odice, ou une version inférieure de la
  MÊME branche majeure. Zammad n'autorise pas de saut de majeure : depuis une
  6.x, il faut d'abord monter le serveur en 7.0.
HINT
  exit 0
fi

mkdir -p "${OUT_DIR}"
TIMESTAMP="$(date +'%Y%m%d%H%M%S')"

echo "== Export de la base de données"
# --no-owner / --no-privileges : sans eux, le dump porte des `ALTER … OWNER TO`
# et des `GRANT` visant le rôle PostgreSQL du serveur. S'il diffère de celui de
# la pile locale, la restauration — qui tourne avec ON_ERROR_STOP=1 — s'arrête
# dessus. Ces deux options rendent le dump portable.
remote "docker compose exec -T ${SVC_PG} sh -c \
  'pg_dump --no-owner --no-privileges -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\"' | gzip" \
  > "${OUT_DIR}/${TIMESTAMP}_zammad_db.psql.gz"
ls -lh "${OUT_DIR}/${TIMESTAMP}_zammad_db.psql.gz"
echo

if [ "${WITH_FILES}" = true ]; then
  echo "== Export des fichiers"
  # L'arborescence de l'archive doit être `opt/zammad/storage` depuis la racine :
  # c'est ce que la restauration désarchive (backup.sh:100).
  remote "docker compose exec -T ${SVC_RAILS} tar -czf - -C / opt/zammad/storage" \
    > "${OUT_DIR}/${TIMESTAMP}_zammad_files.tar.gz"
  ls -lh "${OUT_DIR}/${TIMESTAMP}_zammad_files.tar.gz"
  echo

  # Une archive tronquée par une coupure SSH ne se voit pas à l'œil nu.
  echo "-- Contrôle d'intégrité de l'archive"
  gzip -t "${OUT_DIR}/${TIMESTAMP}_zammad_files.tar.gz" && echo "   archive valide"
fi

echo "-- Contrôle d'intégrité du dump"
gzip -t "${OUT_DIR}/${TIMESTAMP}_zammad_db.psql.gz" && echo "   dump valide"

echo
echo "Export terminé :"
ls -lh "${OUT_DIR}" | grep "${TIMESTAMP}" || true
echo
echo "Étape suivante — vérification sur la pile locale :"
echo "  contrib/odice/restore-local.sh --from ${OUT_DIR}"
