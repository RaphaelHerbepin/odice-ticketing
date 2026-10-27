# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Réservé aux agents. La règle fine (sa propre note, interne, ticket
# modifiable) est vérifiée dans le contrôleur, sur l'article lui-même.
class Controllers::Odice::ArticleNotesControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('ticket.agent')
end
