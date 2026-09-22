# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket
  class StatisticsType < Gql::Types::BaseObject
    description 'Aggregated ticket statistics, scoped to the tickets the current user may read'

    field :period, Gql::Types::Ticket::Statistics::PeriodType, null: false, description: 'Period analysed and the time step actually used'
    field :totals, Gql::Types::Ticket::Statistics::TotalsType, null: false, description: 'Headline figures'

    field :by_group, [Gql::Types::Ticket::Statistics::BucketType], null: false, description: 'Ticket count per group (service)'
    field :by_organization, [Gql::Types::Ticket::Statistics::BucketType], null: false, description: 'Ticket count per organization'
    field :by_state, [Gql::Types::Ticket::Statistics::BucketType], null: false, description: 'Ticket count per state'
    field :by_priority, [Gql::Types::Ticket::Statistics::BucketType], null: false, description: 'Ticket count per priority'
    field :by_owner, [Gql::Types::Ticket::Statistics::BucketType], null: false, description: 'Ticket count per owning agent'
    field :by_channel, [Gql::Types::Ticket::Statistics::BucketType], null: false, description: 'Ticket count per creation channel'

    field :by_axis, [Gql::Types::Ticket::Statistics::AxisType], null: false, description: 'Breakdowns along the business axes requested by the caller'
    field :volume_over_time, [Gql::Types::Ticket::Statistics::VolumePointType], null: false, description: 'Created and closed counts, and time logged, per period'
  end
end
