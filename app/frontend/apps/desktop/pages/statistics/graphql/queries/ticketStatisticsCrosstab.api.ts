import * as Types from '#shared/graphql/types.ts';

import gql from 'graphql-tag';
import * as VueApolloComposable from '@vue/apollo-composable';
import * as VueCompositionApi from 'vue';
export type ReactiveFunction<TParam> = () => TParam;

export const TicketStatisticsCrosstabDocument = gql`
    query ticketStatisticsCrosstab($rowAxis: String!, $columnAxis: String!, $from: ISO8601DateTime, $to: ISO8601DateTime, $axisFilters: [TicketStatisticsAxisFilterInput!]) {
  ticketStatisticsCrosstab(
    rowAxis: $rowAxis
    columnAxis: $columnAxis
    from: $from
    to: $to
    axisFilters: $axisFilters
  ) {
    rowAxis {
      name
      label
    }
    columnAxis {
      name
      label
    }
    columns {
      value
      label
      count
    }
    rows {
      value
      label
      total
      cells
    }
    total
  }
}
    `;
export function useTicketStatisticsCrosstabQuery(variables: Types.TicketStatisticsCrosstabQueryVariables | VueCompositionApi.Ref<Types.TicketStatisticsCrosstabQueryVariables> | ReactiveFunction<Types.TicketStatisticsCrosstabQueryVariables>, options: VueApolloComposable.UseQueryOptions<Types.TicketStatisticsCrosstabQuery, Types.TicketStatisticsCrosstabQueryVariables> | VueCompositionApi.Ref<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsCrosstabQuery, Types.TicketStatisticsCrosstabQueryVariables>> | ReactiveFunction<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsCrosstabQuery, Types.TicketStatisticsCrosstabQueryVariables>> = {}) {
  return VueApolloComposable.useQuery<Types.TicketStatisticsCrosstabQuery, Types.TicketStatisticsCrosstabQueryVariables>(TicketStatisticsCrosstabDocument, variables, options);
}
export function useTicketStatisticsCrosstabLazyQuery(variables?: Types.TicketStatisticsCrosstabQueryVariables | VueCompositionApi.Ref<Types.TicketStatisticsCrosstabQueryVariables> | ReactiveFunction<Types.TicketStatisticsCrosstabQueryVariables>, options: VueApolloComposable.UseQueryOptions<Types.TicketStatisticsCrosstabQuery, Types.TicketStatisticsCrosstabQueryVariables> | VueCompositionApi.Ref<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsCrosstabQuery, Types.TicketStatisticsCrosstabQueryVariables>> | ReactiveFunction<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsCrosstabQuery, Types.TicketStatisticsCrosstabQueryVariables>> = {}) {
  return VueApolloComposable.useLazyQuery<Types.TicketStatisticsCrosstabQuery, Types.TicketStatisticsCrosstabQueryVariables>(TicketStatisticsCrosstabDocument, variables, options);
}
export type TicketStatisticsCrosstabQueryCompositionFunctionResult = VueApolloComposable.UseQueryReturn<Types.TicketStatisticsCrosstabQuery, Types.TicketStatisticsCrosstabQueryVariables>;