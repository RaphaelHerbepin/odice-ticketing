# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — export des statistiques.
#
# Un contrôleur REST plutôt qu'une mutation GraphQL : la réponse est un fichier
# binaire que le navigateur doit télécharger, ce que GraphQL ne transporte pas.
# `config/routes.rb` charge ce fichier avant la route attrape-tout des erreurs.
Zammad::Application.routes.draw do
  scope Rails.configuration.api_path do
    get 'ticket_statistics/download', to: 'ticket/statistics#download'
  end
end
