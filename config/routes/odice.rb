# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — routes propres au fork. Fichier découvert automatiquement par
# config/routes.rb (glob config/routes/*.rb) : aucun fichier Zammad modifié.
Zammad::Application.routes.draw do
  api_path = Rails.configuration.api_path

  # Modification de ses propres notes internes (interface /desktop).
  match api_path + '/odice/article_notes/:id', to: 'odice/article_notes#update', via: :put

  # Identifiants des états de type « clos » (proposition de solution à la clôture).
  match api_path + '/odice/closed_state_ids', to: 'odice/article_notes#closed_state_ids', via: :get

  # Enquête de satisfaction : page PUBLIQUE, protégée par un jeton signé.
  match '/odice/satisfaction/:token', to: 'odice/satisfaction#show', via: :get, as: :odice_satisfaction
  match '/odice/satisfaction/:token', to: 'odice/satisfaction#create', via: :post
end
