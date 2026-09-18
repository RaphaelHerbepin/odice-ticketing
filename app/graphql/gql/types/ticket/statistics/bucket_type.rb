# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket::Statistics
  class BucketType < Gql::Types::BaseObject
    description 'Ticket count for one value of a grouping axis'

    field :id, Integer, null: false, description: 'Identifier of the grouped record'
    field :label, String, null: false, description: 'Human readable label of the grouped record'
    field :count, Integer, null: false, description: 'Number of tickets in this bucket'
  end
end
