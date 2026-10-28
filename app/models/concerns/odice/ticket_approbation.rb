# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — validation des demandes de matériel par le responsable de l'agence.
#
# Les responsables sont des personnes des agences, le plus souvent sans compte
# agent (parfois sans compte du tout) : ils décident depuis une page publique,
# atteinte par un lien SIGNÉ propre au ticket, envoyé par le déclencheur
# « 40 - Matériel : validation <agence> ». Voir Odice::ApprobationController.
#
# Le responsable de chaque agence est lu dans le réglage
# `odice_approbateurs_materiel` ({ agence => e-mail }), écrit par
# scripts/setup-demande-materiel.rb ; le même script en tire les déclencheurs.
module Odice::TicketApprobation
  extend ActiveSupport::Concern

  PURPOSE   = :odice_approbation
  SETTING   = 'odice_approbateurs_materiel'.freeze
  DECISIONS = { 'valider' => 'Approuvé', 'refuser' => 'Refusé' }.freeze

  def self.verifier
    @verifier ||= ActiveSupport::MessageVerifier.new(
      Rails.application.key_generator.generate_key('odice-approbation'),
      digest: 'SHA256', url_safe: true, serializer: JSON,
    )
  end

  def self.token_for(ticket)
    verifier.generate(ticket.id, purpose: PURPOSE)
  end

  def self.ticket_for(token)
    id = verifier.verified(token.to_s, purpose: PURPOSE)
    id && ::Ticket.find_by(id: id)
  end

  def self.approbateurs
    (Setting.get(SETTING).presence || {}).to_h
  rescue StandardError
    {}
  end

  def self.approbateur_for(ticket)
    approbateurs[ticket.try(:agence).to_s].presence || approbateurs['*'].presence
  end

  # Lien de décision. Dans un gabarit : #{ticket.odice_approbation_url}
  # (1 = valider, 2 = refuser, pour présélectionner la décision).
  def odice_approbation_url(choix = nil)
    base = "#{Setting.get('http_type')}://#{Setting.get('fqdn')}/odice/approbation/#{Odice::TicketApprobation.token_for(self)}"
    case choix.to_i
    when 1 then "#{base}?decision=valider"
    when 2 then "#{base}?decision=refuser"
    else base
    end
  end
end
