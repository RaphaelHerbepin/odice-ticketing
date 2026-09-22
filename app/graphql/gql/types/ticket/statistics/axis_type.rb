# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket::Statistics
  class AxisType < Gql::Types::BaseObject
    description 'Ticket counts broken down along a business axis (agency, department, request subject…)'

    field :name, String, null: false, description: 'Logical axis name, as accepted by the query argument'
    field :label, String, null: false, description: 'Human readable axis name, from the object attribute definition'
    field :buckets, [Gql::Types::Ticket::Statistics::AxisBucketType], null: false, description: 'Counts per distinct value, most frequent first'
  end
end
