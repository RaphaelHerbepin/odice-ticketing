# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket::Statistics
  class AxisDefinitionType < Gql::Types::BaseObject
    description 'A business axis that ticket statistics can be broken down by'

    field :name, String, null: false, description: 'Logical name to pass to the statistics query'
    field :label, String, null: false, description: 'Human readable name, from the object attribute definition'
    # Taken from the field definition, NOT from the buckets of a breakdown:
    # those come from the already filtered query, so picking one value would
    # make every other one disappear from the list.
    field :values, [Gql::Types::Ticket::Statistics::AxisValueType], null: false, description: 'Selectable values, as defined by the administrator'
  end
end
