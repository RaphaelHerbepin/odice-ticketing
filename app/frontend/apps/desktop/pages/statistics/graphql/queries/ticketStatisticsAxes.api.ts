import * as Types from '#shared/graphql/types.ts';

import gql from 'graphql-tag';
import * as VueApolloComposable from '@vue/apollo-composable';
import * as VueCompositionApi from 'vue';
export type ReactiveFunction<TParam> = () => TParam;

export const TicketStatisticsAxesDocument = gql`
    query ticketStatisticsAxes {
  ticketStatisticsAxes {
    name
    label
  }
}
    `;
export function useTicketStatisticsAxesQuery(options: VueApolloComposable.UseQueryOptions<Types.TicketStatisticsAxesQuery, Types.TicketStatisticsAxesQueryVariables> | VueCompositionApi.Ref<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsAxesQuery, Types.TicketStatisticsAxesQueryVariables>> | ReactiveFunction<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsAxesQuery, Types.TicketStatisticsAxesQueryVariables>> = {}) {
  return VueApolloComposable.useQuery<Types.TicketStatisticsAxesQuery, Types.TicketStatisticsAxesQueryVariables>(TicketStatisticsAxesDocument, {}, options);
}
export function useTicketStatisticsAxesLazyQuery(options: VueApolloComposable.UseQueryOptions<Types.TicketStatisticsAxesQuery, Types.TicketStatisticsAxesQueryVariables> | VueCompositionApi.Ref<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsAxesQuery, Types.TicketStatisticsAxesQueryVariables>> | ReactiveFunction<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsAxesQuery, Types.TicketStatisticsAxesQueryVariables>> = {}) {
  return VueApolloComposable.useLazyQuery<Types.TicketStatisticsAxesQuery, Types.TicketStatisticsAxesQueryVariables>(TicketStatisticsAxesDocument, {}, options);
}
export type TicketStatisticsAxesQueryCompositionFunctionResult = VueApolloComposable.UseQueryReturn<Types.TicketStatisticsAxesQuery, Types.TicketStatisticsAxesQueryVariables>;