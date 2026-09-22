# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Queries
  class Ticket::Statistics::Crosstab < BaseQuery

    description 'Ticket counts crossed over two business axes'

    # A top-level query rather than a field of TicketStatistics: it is asked for
    # from its own tab, and the overview has no reason to pay for an aggregate
    # it does not display.
    argument :row_axis, String, required: true, description: 'Logical axis name for the rows'
    argument :column_axis, String, required: true, description: 'Logical axis name for the columns'
    argument :from, GraphQL::Types::ISO8601DateTime, required: false
    argument :to, GraphQL::Types::ISO8601DateTime, required: false
    argument :group_ids, [GraphQL::Types::ID], required: false
    argument :organization_ids, [GraphQL::Types::ID], required: false
    argument :axis_filters, [Gql::Types::Input::Ticket::Statistics::AxisFilterInputType], required: false, description: 'Restrict to tickets matching these business axis values'

    type Gql::Types::Ticket::Statistics::CrosstabType, null: false

    def self.authorize(_obj, ctx)
      ctx.current_user.permissions?('ticket.agent')
    end

    def resolve(row_axis:, column_axis:, from: nil, to: nil, group_ids: nil, organization_ids: nil, axis_filters: nil)
      Service::Ticket::Statistics::Crosstab
        .with_current_user(context.current_user)
        .execute(row_axis:, column_axis:, from:, to:, group_ids:, organization_ids:,
                 axis_filters: axis_filters&.map(&:to_h))
    end
  end
end
