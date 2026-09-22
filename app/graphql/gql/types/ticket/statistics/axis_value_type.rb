# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket::Statistics
  class AxisValueType < Gql::Types::BaseObject
    description 'One selectable value of a business axis, as defined by the administrator'

    # The raw stored value — this is what goes back in an axis filter. For a
    # tree field it is the full path ("Windows::Imprimante"), never the label.
    field :value, String, null: false, description: 'Stored value, to pass back as an axis filter'
    field :label, String, null: false, description: 'Human readable label; tree paths use a chevron'
  end
end
