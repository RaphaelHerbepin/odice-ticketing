# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Queries
  class Ticket::Statistics < BaseQuery

    description 'Aggregated ticket statistics for reporting'

    argument :from, GraphQL::Types::ISO8601DateTime, required: false, description: 'Start of the period (defaults to 30 days ago)'
    argument :to, GraphQL::Types::ISO8601DateTime, required: false, description: 'End of the period (defaults to now)'
    argument :group_ids, [GraphQL::Types::ID], required: false, description: 'Restrict to these groups'
    argument :organization_ids, [GraphQL::Types::ID], required: false, description: 'Restrict to these organizations'
    # Logical axis names only. The service resolves them against a whitelist
    # built from ObjectManager::Attribute and rejects anything else: a column
    # name cannot be a bound parameter, so it must never come from the client.
    argument :axes, [String], required: false, description: 'Business axes to break down by, e.g. agence, service_demandeur'
    # Interpolated into a DATE_TRUNC, so the service checks it against its own
    # whitelist and silently falls back to a step chosen from the period length.
    argument :interval, String, required: false, description: 'Time step for the series: day, week or month. Chosen from the period length when omitted'

    type Gql::Types::Ticket::StatisticsType, null: false

    # The service scopes every query through TicketPolicy::ReadScope, so an
    # agent only ever aggregates tickets they are allowed to read.
    def self.authorize(_obj, ctx)
      ctx.current_user.permissions?('ticket.agent')
    end

    def resolve(from: nil, to: nil, group_ids: nil, organization_ids: nil, axes: nil, interval: nil)
      Service::Ticket::Statistics
        .with_current_user(context.current_user)
        .execute(from:, to:, group_ids:, organization_ids:, axes:, interval:)
    end
  end
end
