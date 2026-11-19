# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Input::Ticket
  class OverviewColumnFilterInputType < Gql::Types::BaseInputObject
    description 'Filter applied to one column of a ticket overview, on its displayed value'

    argument :column, String, description: 'Column (ticket attribute) name, e.g. title, customer_id or a custom attribute'
    argument :operator, Gql::Types::Enum::TicketOverviewColumnFilterOperatorType, description: 'Comparison to apply'
    argument :value, String, required: false, description: 'Text to compare with (case and accent insensitive)'
  end
end
