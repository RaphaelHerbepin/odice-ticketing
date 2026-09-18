# Odice — variables d'environnement du développement local.
# À sourcer AVANT `bin/setup` et `bin/dev` :  source docker/dev/env.sh
#
# Le dépôt n'embarque pas de gem dotenv : il n'y a pas de chargement
# automatique, d'où ce script.

# Le nom de la base est volontairement absent de DATABASE_URL : c'est la
# convention du devcontainer amont, qui laisse config/database.yml fournir
# zammad_development et zammad_test. Ne pas définir les POSTGRESQL_* ici, sinon
# config/pre_initializers/database_url.rb prend le relais et ignore ce réglage.
export DATABASE_URL="postgres://zammad:zammad@127.0.0.1:${ODICE_DEV_PG_PORT:-5432}"
export REDIS_URL="redis://127.0.0.1:${ODICE_DEV_REDIS_PORT:-6379}"
export MEMCACHE_SERVERS="127.0.0.1:${ODICE_DEV_MEMCACHED_PORT:-11211}"
export ES_URL="http://127.0.0.1:${ODICE_DEV_ES_PORT:-9200}"
export ES_INDEX="odice_development"

export Z_LOCALES="fr-fr:en-us"
export TZ="Europe/Paris"
export VITE_RUBY_HOST="127.0.0.1"
