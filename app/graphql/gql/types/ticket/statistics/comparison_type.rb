# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket::Statistics
  class ComparisonType < Gql::Types::BaseObject
    description 'The same figures over the immediately preceding period of equal length'

    # The client never recomputes these bounds: it would land a few seconds off
    # the ones the server actually queried, and the label under each card would
    # then name a period that was not the one measured.
    field :from, GraphQL::Types::ISO8601DateTime, null: false, description: 'Start of the preceding period'
    field :to, GraphQL::Types::ISO8601DateTime, null: false, description: 'End of the preceding period'

    # Flow and quality only. `open`, `closed` and `escalated` are deliberately
    # absent: they are states observed TODAY over a cohort defined by creation
    # date. Tickets created last month had a month longer to be dealt with, so
    # comparing the two windows measures how old the tickets are, not how well
    # the team did — and would announce a spectacular improvement every month,
    # for ever. The type refuses to answer the misleading question.
    field :total, Integer, null: false, description: 'Tickets created in the preceding period'
    field :average_first_response_minutes, Float, null: true
    field :average_close_minutes, Float, null: true
    field :first_response_in_time_percent, Float, null: true
    field :close_in_time_percent, Float, null: true
    field :time_logged_minutes, Float, null: true
    field :time_coverage_percent, Float, null: true
  end
end
