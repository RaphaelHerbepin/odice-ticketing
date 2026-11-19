# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Enum
  class TicketOverviewColumnFilterOperatorType < BaseEnum
    description 'Comparison applied by a ticket overview column filter'

    value 'CONTAINS',     'Displayed value contains the given text', value: 'contains'
    value 'NOT_CONTAINS', 'Displayed value does not contain the given text', value: 'not_contains'
    value 'STARTS_WITH',  'Displayed value starts with the given text', value: 'starts_with'
    value 'ENDS_WITH',    'Displayed value ends with the given text', value: 'ends_with'
    value 'EQUALS',       'Displayed value equals the given text', value: 'equals'
    value 'NOT_EQUALS',   'Displayed value differs from the given text', value: 'not_equals'
    value 'IS_EMPTY',     'Displayed value is empty', value: 'is_empty'
    value 'IS_NOT_EMPTY', 'Displayed value is not empty', value: 'is_not_empty'
  end
end
