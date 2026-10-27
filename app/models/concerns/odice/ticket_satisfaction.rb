# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — enquête de satisfaction envoyée à la clôture.
#
# Le lien de l'e-mail porte un jeton SIGNÉ (identifiant du ticket + objet) :
# impossible d'en fabriquer un pour un autre ticket, et inutile de stocker un
# jeton en base. Le déclencheur de clôture l'insère par
#   #{ticket.odice_satisfaction_url(4)}
# le moteur de notification acceptant une méthode publique à un argument entier.
#
# Les réponses vont dans deux champs du ticket créés par
# scripts/setup-satisfaction.rb : `satisfaction_note` (liste 1 à 5, donc axe
# des statistiques) et `satisfaction_commentaire`.
module Odice::TicketSatisfaction
  extend ActiveSupport::Concern

  PURPOSE = :odice_satisfaction
  NOTES   = (1..5).freeze

  def self.verifier
    @verifier ||= ActiveSupport::MessageVerifier.new(
      Rails.application.key_generator.generate_key('odice-satisfaction'),
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

  def self.enabled?
    ::Ticket.column_names.include?('satisfaction_note')
  end

  def odice_satisfaction_url(note = nil)
    base  = "#{Setting.get('http_type')}://#{Setting.get('fqdn')}/odice/satisfaction/#{Odice::TicketSatisfaction.token_for(self)}"
    value = note.to_i
    NOTES.cover?(value) ? "#{base}?note=#{value}" : base
  end
end
