# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket::Statistics
  class CrosstabType < Gql::Types::BaseObject
    description 'Ticket counts crossed over two business axes'

    field :row_axis, Gql::Types::Ticket::Statistics::CrosstabAxisType, null: false
    field :column_axis, Gql::Types::Ticket::Statistics::CrosstabAxisType, null: false

    # `count` here is the column total, across every row.
    field :columns, [Gql::Types::Ticket::Statistics::AxisBucketType], null: false, description: 'Column headers and their totals, in display order'
    field :rows, [Gql::Types::Ticket::Statistics::CrosstabRowType], null: false, description: 'Rows in display order; cells follow the column order'
    # Includes the Others row and column, so the client can check its own
    # rendering: the cells must add up to exactly this.
    field :total, Integer, null: false, description: 'Grand total, Others included'
  end
end
