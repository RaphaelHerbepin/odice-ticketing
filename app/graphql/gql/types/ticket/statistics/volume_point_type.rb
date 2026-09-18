# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket::Statistics
  class VolumePointType < Gql::Types::BaseObject
    description 'Created and closed ticket counts for a single day'

    field :date, String, null: false, description: 'Day in ISO 8601 format'
    field :created, Integer, null: false, description: 'Tickets created on that day'
    field :closed, Integer, null: false, description: 'Tickets closed on that day'
  end
end
