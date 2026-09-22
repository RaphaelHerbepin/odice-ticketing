import * as Types from '#shared/graphql/types.ts';

import gql from 'graphql-tag';
import * as VueApolloComposable from '@vue/apollo-composable';
import * as VueCompositionApi from 'vue';
export type ReactiveFunction<TParam> = () => TParam;

export const TicketStatisticsDocument = gql`
    query ticketStatistics($from: ISO8601DateTime, $to: ISO8601DateTime, $groupIds: [ID!], $organizationIds: [ID!], $axes: [String!], $interval: String, $axisFilters: [TicketStatisticsAxisFilterInput!], $compare: Boolean) {
  ticketStatistics(
    from: $from
    to: $to
    groupIds: $groupIds
    organizationIds: $organizationIds
    axes: $axes
    interval: $interval
    axisFilters: $axisFilters
    compare: $compare
  ) {
    period {
      from
      to
      interval
    }
    totals {
      total
      open
      closed
      escalated
      averageFirstResponseMinutes
      averageCloseMinutes
      firstResponseInTimePercent
      closeInTimePercent
      timeLoggedMinutes
      timeCoveragePercent
    }
    comparison {
      from
      to
      total
      averageFirstResponseMinutes
      averageCloseMinutes
      firstResponseInTimePercent
      closeInTimePercent
      timeLoggedMinutes
      timeCoveragePercent
    }
    byGroup {
      label
      count
    }
    byOrganization {
      label
      count
    }
    byState {
      label
      count
    }
    byPriority {
      label
      count
    }
    byOwner {
      label
      count
    }
    byChannel {
      label
      count
    }
    byAxis {
      name
      label
      buckets {
        value
        label
        count
      }
    }
    volumeOverTime {
      date
      created
      closed
      timeLoggedMinutes
    }
  }
}
    `;
export function useTicketStatisticsQuery(variables: Types.TicketStatisticsQueryVariables | VueCompositionApi.Ref<Types.TicketStatisticsQueryVariables> | ReactiveFunction<Types.TicketStatisticsQueryVariables> = {}, options: VueApolloComposable.UseQueryOptions<Types.TicketStatisticsQuery, Types.TicketStatisticsQueryVariables> | VueCompositionApi.Ref<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsQuery, Types.TicketStatisticsQueryVariables>> | ReactiveFunction<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsQuery, Types.TicketStatisticsQueryVariables>> = {}) {
  return VueApolloComposable.useQuery<Types.TicketStatisticsQuery, Types.TicketStatisticsQueryVariables>(TicketStatisticsDocument, variables, options);
}
export function useTicketStatisticsLazyQuery(variables: Types.TicketStatisticsQueryVariables | VueCompositionApi.Ref<Types.TicketStatisticsQueryVariables> | ReactiveFunction<Types.TicketStatisticsQueryVariables> = {}, options: VueApolloComposable.UseQueryOptions<Types.TicketStatisticsQuery, Types.TicketStatisticsQueryVariables> | VueCompositionApi.Ref<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsQuery, Types.TicketStatisticsQueryVariables>> | ReactiveFunction<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsQuery, Types.TicketStatisticsQueryVariables>> = {}) {
  return VueApolloComposable.useLazyQuery<Types.TicketStatisticsQuery, Types.TicketStatisticsQueryVariables>(TicketStatisticsDocument, variables, options);
}
export type TicketStatisticsQueryCompositionFunctionResult = VueApolloComposable.UseQueryReturn<Types.TicketStatisticsQuery, Types.TicketStatisticsQueryVariables>;