# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket::Statistics
  class AgentType < Gql::Types::BaseObject
    description 'Per-agent workload and delays'

    field :id, GraphQL::Types::ID, null: false, description: 'User id of the agent'
    field :label, String, null: false, description: 'Agent full name'

    # Stock — instantané, indépendant de la période demandée.
    field :open, Integer, null: false, description: 'Tickets currently open and owned by this agent'
    field :escalated, Integer, null: false, description: 'Of those, currently escalated'
    field :dormant, Integer, null: false, description: 'Of those, untouched for three days or more'

    # Flux — sur la période demandée.
    field :received, Integer, null: false, description: 'Tickets created in the period and owned by this agent'
    field :closed, Integer, null: false, description: 'Tickets closed in the period'
    field :average_first_response_minutes, Float, null: true, description: 'Mean first response time, in minutes'
    field :average_close_minutes, Float, null: true, description: 'Mean time to close, in minutes'
    field :close_in_time_percent, Float, null: true, description: 'Share of closures meeting their target'

    # Attribué à qui a SAISI le temps, pas au propriétaire du ticket : les deux
    # chiffres répondent à deux questions distinctes et ne s'additionnent pas.
    field :time_logged_minutes, Float, null: true, description: 'Time logged by this agent in the period'
  end
end
