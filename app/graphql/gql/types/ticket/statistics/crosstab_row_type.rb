# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket::Statistics
  class CrosstabRowType < Gql::Types::BaseObject
    description 'One row of a crosstab'

    field :value, String, null: true, description: 'Stored value; null for "not set" and for the Others row'
    field :label, String, null: false
    field :total, Integer, null: false, description: 'Row total, across every column'

    # Positional: cells[j] belongs to columns[j] of the enclosing crosstab, in
    # that exact order, and is zero rather than null when empty. A list of
    # objects would send a hundred column names for a hundred integers, when
    # the order IS the information.
    field :cells, [Integer], null: false, description: 'One count per entry of `columns`, in the same order'
  end
end
