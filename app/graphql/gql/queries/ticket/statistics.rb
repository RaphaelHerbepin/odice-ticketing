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
    # Interpolated into no SQL directly, but the axis NAME designates a column:
    # the service resolves every entry against the Axes whitelist and refuses
    # anything else. See Service::Ticket::Statistics::AxisFilter.
    # Opt-in: the comparison costs a second pass of the headline aggregates, and
    # the views that do not display an evolution should not pay for it.
    argument :compare, Boolean, required: false, default_value: false, description: 'Also compute the same figures over the preceding period'
    argument :axis_filters, [Gql::Types::Input::Ticket::Statistics::AxisFilterInputType], required: false, description: 'Restrict to tickets matching these business axis values'

    type Gql::Types::Ticket::StatisticsType, null: false

    # The service scopes every query through TicketPolicy::ReadScope, so an
    # agent only ever aggregates tickets they are allowed to read.
    def self.authorize(_obj, ctx)
      ctx.current_user.permissions?('ticket.agent')
    end

    def resolve(from: nil, to: nil, group_ids: nil, organization_ids: nil, axes: nil, interval: nil, axis_filters: nil, compare: false)
      Service::Ticket::Statistics
        .with_current_user(context.current_user)
        .execute(from:, to:, group_ids:, organization_ids:, axes:, interval:, compare:, axis_filters: axis_filters&.map(&:to_h))
    end
  end
end
