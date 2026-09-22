# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket::Statistics
  class PeriodType < Gql::Types::BaseObject
    description 'The period analysed, and the time step the server actually applied'

    field :from, GraphQL::Types::ISO8601DateTime, null: false, description: 'Start of the period'
    field :to, GraphQL::Types::ISO8601DateTime, null: false, description: 'End of the period'
    # The client asks for a step or lets the server choose one; either way it
    # needs to know which was used, since the axis labels depend on it.
    field :interval, String, null: false, description: 'Time step used: day, week or month'
  end
end
