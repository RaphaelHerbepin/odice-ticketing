# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket::Statistics
  # Distinct de `BucketType` à dessein : celui-ci regroupe des enregistrements et
  # porte un identifiant entier obligatoire, alors qu'un axe métier regroupe des
  # VALEURS textuelles, éventuellement absentes. Réutiliser `BucketType` obligeait
  # à renvoyer `id: nil` sur un champ déclaré non nullable — une erreur GraphQL dès
  # qu'un client demanderait ce champ.
  class AxisBucketType < Gql::Types::BaseObject
    description 'Ticket count for one distinct value of a business axis'

    field :value, String, null: true, description: 'Raw stored value, null when the field is empty'
    field :label, String, null: false, description: 'Value as shown to the user'
    field :count, Integer, null: false, description: 'Number of tickets with this value'
  end
end
