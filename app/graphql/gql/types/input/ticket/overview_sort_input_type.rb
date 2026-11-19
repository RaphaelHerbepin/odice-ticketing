# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Input::Ticket
  class OverviewSortInputType < Gql::Types::BaseInputObject
    description 'One level of a multi-column sort of a ticket overview'

    argument :column, String, description: 'Column (ticket attribute) name, e.g. title, customer_id or a custom attribute'
    argument :direction, Gql::Types::Enum::OrderDirectionType, description: 'Sort direction'
  end
end
