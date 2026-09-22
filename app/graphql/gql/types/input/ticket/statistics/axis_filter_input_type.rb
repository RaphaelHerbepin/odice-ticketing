# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Input::Ticket::Statistics
  class AxisFilterInputType < Gql::Types::BaseInputObject
    description 'Restriction on one business axis. Values are OR-ed together; separate entries are AND-ed.'

    argument :name, String, required: true, description: 'Logical axis name, as returned by ticketStatisticsAxes'
    # Null elements are allowed on purpose: a null (or empty) value means "field
    # not set", which the breakdowns show as a bucket and must stay filterable.
    argument :values, [String, { null: true }], required: true, description: 'Accepted values; null or an empty string means "not set"'
  end
end
