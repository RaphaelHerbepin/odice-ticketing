#!/bin/bash
# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/
# Hook: regenerate generated files when their sources change.

# Claude Code invokes this script outside of an interactive shell, so rv's
#   PROMPT_COMMAND-based version switching never runs; re-resolve it here.
#   Needed before the pnpm generate-* calls below, which shell out to
#   `bundle exec rails generate ...` and inherit this process's env.
if command -v rv >/dev/null 2>&1; then
  RV_ENV=$(rv shell env bash) || { echo "rv shell env bash failed to resolve the Ruby environment" >&2; exit 2; }
  eval "$RV_ENV"
fi

# --- Garde-fous ajoutés pour Odice ---------------------------------------
# 1. Anti-boucle. Quand un hook Stop échoue, Claude Code relance le modèle pour
#    qu'il corrige ; si la cause n'est pas corrigeable (un outil absent), la
#    boucle ne s'arrête jamais. Le champ `stop_hook_active` du JSON reçu sur
#    stdin vaut true dans ces relances : on sort alors en succès.
if [ ! -t 0 ]; then
  HOOK_INPUT=$(cat 2>/dev/null)
  if printf '%s' "$HOOK_INPUT" | grep -qE '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
    exit 0
  fi
fi

# 2. Les gems du Gemfile sont-elles installées ? `bundle check` est le bon test
#    ici : `bundle --version` répond même quand rien n'est installé, alors que
#    c'est précisément ce dont rubocop et `rails generate` ont besoin. Sur ce
#    poste, Ruby est en 3.4.2 quand le projet exige 3.4.9, donc `bundle install`
#    n'a jamais abouti. Les étapes Ruby sont ignorées avec un avertissement, au
#    lieu de faire échouer tout le hook — les étapes frontend fonctionnent.
if bundle check >/dev/null 2>&1; then
  BUNDLER_OK=true
else
  BUNDLER_OK=false
fi
# -------------------------------------------------------------------------

CHANGED_FILES=$(git diff --name-only --diff-filter=ACMR HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)

NEEDS_GRAPHQL=false
NEEDS_SETTINGS=false

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  case "$file" in
    app/graphql/*)          NEEDS_GRAPHQL=true ;;
    app/frontend/*.graphql) NEEDS_GRAPHQL=true ;;
    app/models/setting.rb)  NEEDS_SETTINGS=true ;;
    db/seeds/settings.rb)   NEEDS_SETTINGS=true ;;
  esac
done <<< "$CHANGED_FILES"

EXIT_CODE=0

# Les deux régénérations passent par `bundle exec rails generate` : sans
# bundler, elles ne peuvent pas aboutir. On le signale une fois, sans échouer.
if ! $BUNDLER_OK && ( $NEEDS_GRAPHQL || $NEEDS_SETTINGS ); then
  echo "[hook] bundler indisponible — régénération ignorée (Ruby 3.4.9 requis)." >&2
  echo "[hook] En Docker : docker compose run --rm zammad-railsserver ..." >&2
  exit 0
fi

if $NEEDS_GRAPHQL; then
  echo "GraphQL schema changed — regenerating types..." >&2
  pnpm generate-graphql-api >&2 || EXIT_CODE=2
fi

if $NEEDS_SETTINGS; then
  echo "Settings changed — regenerating types..." >&2
  pnpm generate-setting-types >&2 || EXIT_CODE=2
fi

exit $EXIT_CODE
