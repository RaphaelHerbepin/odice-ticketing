# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — branche l'enquête de satisfaction et la validation des demandes de
# matériel sur le modèle Ticket sans modifier
# app/models/ticket.rb. `to_prepare` rejoue l'inclusion à chaque rechargement.
Rails.application.config.to_prepare do
  Ticket.include(Odice::TicketSatisfaction) if !Ticket.include?(Odice::TicketSatisfaction)
  Ticket.include(Odice::TicketApprobation) if !Ticket.include?(Odice::TicketApprobation)
end
