# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket::Statistics
  class TotalsType < Gql::Types::BaseObject
    description 'Headline figures for the selected period'

    field :total, Integer, null: false, description: 'Tickets created in the period'
    field :open, Integer, null: false, description: 'Tickets not in a closed state'
    field :closed, Integer, null: false, description: 'Tickets in a closed state'
    field :escalated, Integer, null: false, description: 'Tickets past their escalation time'

    field :average_first_response_minutes, Float, null: true, description: 'Mean time to first response, in minutes'
    field :average_close_minutes, Float, null: true, description: 'Mean time to closure, in minutes'
    field :first_response_in_time_percent, Float, null: true, description: 'Share of tickets meeting the first response target'
    field :close_in_time_percent, Float, null: true, description: 'Share of tickets meeting the closure target'
  end
end
