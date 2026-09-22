# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket::Statistics
  class CrosstabAxisType < Gql::Types::BaseObject
    description 'The axis a crosstab dimension was built on'

    # Deliberately not AxisDefinitionType: that one carries the full list of
    # selectable values, which a crosstab has no use for and would send twice.
    field :name, String, null: false
    field :label, String, null: false
  end
end
