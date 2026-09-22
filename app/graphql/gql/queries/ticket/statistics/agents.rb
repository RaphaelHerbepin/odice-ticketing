# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Queries
  class Ticket::Statistics::Agents < BaseQuery
    description 'Per-agent ticket workload and delays'

    argument :from, GraphQL::Types::ISO8601DateTime, required: false, description: 'Start of the period (defaults to 30 days ago)'
    argument :to, GraphQL::Types::ISO8601DateTime, required: false, description: 'End of the period (defaults to now)'
    argument :group_ids, [GraphQL::Types::ID], required: false, description: 'Restrict to these groups'
    argument :organization_ids, [GraphQL::Types::ID], required: false, description: 'Restrict to these organizations'
    # Interpolated into no SQL directly, but the axis NAME designates a column:
    # the service resolves every entry against the Axes whitelist and refuses
    # anything else. See Service::Ticket::Statistics::AxisFilter.
    argument :axis_filters, [Gql::Types::Input::Ticket::Statistics::AxisFilterInputType], required: false, description: 'Restrict to tickets matching these business axis values'

    type [Gql::Types::Ticket::Statistics::AgentType], null: false

    def self.authorize(_obj, ctx)
      ctx.current_user.permissions?('ticket.agent')
    end

    def resolve(from: nil, to: nil, group_ids: nil, organization_ids: nil, axis_filters: nil)
      Service::Ticket::Statistics::Agents
        .with_current_user(context.current_user)
        .execute(from:, to:, group_ids:, organization_ids:, axis_filters: axis_filters&.map(&:to_h))
    end
  end
end
