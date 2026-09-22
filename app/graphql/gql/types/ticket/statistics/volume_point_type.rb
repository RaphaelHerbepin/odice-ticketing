# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket::Statistics
  class VolumePointType < Gql::Types::BaseObject
    description 'Created and closed ticket counts, and time logged, for a single period'

    field :date, String, null: false, description: 'Start of the period in ISO 8601 format'
    field :created, Integer, null: false, description: 'Tickets created in that period'
    field :closed, Integer, null: false, description: 'Tickets closed in that period'
    field :time_logged_minutes, Float, null: false, description: 'Minutes logged in that period'
  end
end
