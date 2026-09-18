# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Queries
  class Ticket::Statistics < BaseQuery

    description 'Aggregated ticket statistics for reporting'

    argument :from, GraphQL::Types::ISO8601DateTime, required: false, description: 'Start of the period (defaults to 30 days ago)'
    argument :to, GraphQL::Types::ISO8601DateTime, required: false, description: 'End of the period (defaults to now)'
    argument :group_ids, [GraphQL::Types::ID], required: false, description: 'Restrict to these groups'
    argument :organization_ids, [GraphQL::Types::ID], required: false, description: 'Restrict to these organizations'

    type Gql::Types::Ticket::StatisticsType, null: false

    # The service scopes every query through TicketPolicy::ReadScope, so an
    # agent only ever aggregates tickets they are allowed to read.
    def self.authorize(_obj, ctx)
      ctx.current_user.permissions?('ticket.agent')
    end

    def resolve(from: nil, to: nil, group_ids: nil, organization_ids: nil)
      Service::Ticket::Statistics
        .with_current_user(context.current_user)
        .execute(from:, to:, group_ids:, organization_ids:)
    end
  end
end
