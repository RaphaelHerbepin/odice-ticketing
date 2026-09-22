import * as Types from '#shared/graphql/types.ts';

import gql from 'graphql-tag';
import * as VueApolloComposable from '@vue/apollo-composable';
import * as VueCompositionApi from 'vue';
export type ReactiveFunction<TParam> = () => TParam;

export const TicketStatisticsAgentsDocument = gql`
    query ticketStatisticsAgents($from: ISO8601DateTime, $to: ISO8601DateTime, $axisFilters: [TicketStatisticsAxisFilterInput!]) {
  ticketStatisticsAgents(from: $from, to: $to, axisFilters: $axisFilters) {
    id
    label
    open
    escalated
    dormant
    received
    closed
    averageFirstResponseMinutes
    averageCloseMinutes
    closeInTimePercent
    timeLoggedMinutes
  }
}
    `;
export function useTicketStatisticsAgentsQuery(variables: Types.TicketStatisticsAgentsQueryVariables | VueCompositionApi.Ref<Types.TicketStatisticsAgentsQueryVariables> | ReactiveFunction<Types.TicketStatisticsAgentsQueryVariables> = {}, options: VueApolloComposable.UseQueryOptions<Types.TicketStatisticsAgentsQuery, Types.TicketStatisticsAgentsQueryVariables> | VueCompositionApi.Ref<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsAgentsQuery, Types.TicketStatisticsAgentsQueryVariables>> | ReactiveFunction<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsAgentsQuery, Types.TicketStatisticsAgentsQueryVariables>> = {}) {
  return VueApolloComposable.useQuery<Types.TicketStatisticsAgentsQuery, Types.TicketStatisticsAgentsQueryVariables>(TicketStatisticsAgentsDocument, variables, options);
}
export function useTicketStatisticsAgentsLazyQuery(variables: Types.TicketStatisticsAgentsQueryVariables | VueCompositionApi.Ref<Types.TicketStatisticsAgentsQueryVariables> | ReactiveFunction<Types.TicketStatisticsAgentsQueryVariables> = {}, options: VueApolloComposable.UseQueryOptions<Types.TicketStatisticsAgentsQuery, Types.TicketStatisticsAgentsQueryVariables> | VueCompositionApi.Ref<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsAgentsQuery, Types.TicketStatisticsAgentsQueryVariables>> | ReactiveFunction<VueApolloComposable.UseQueryOptions<Types.TicketStatisticsAgentsQuery, Types.TicketStatisticsAgentsQueryVariables>> = {}) {
  return VueApolloComposable.useLazyQuery<Types.TicketStatisticsAgentsQuery, Types.TicketStatisticsAgentsQueryVariables>(TicketStatisticsAgentsDocument, variables, options);
}
export type TicketStatisticsAgentsQueryCompositionFunctionResult = VueApolloComposable.UseQueryReturn<Types.TicketStatisticsAgentsQuery, Types.TicketStatisticsAgentsQueryVariables>;