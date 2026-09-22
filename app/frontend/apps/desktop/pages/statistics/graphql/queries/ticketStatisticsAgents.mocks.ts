import * as Types from '#shared/graphql/types.ts';

import * as Mocks from '#tests/graphql/builders/mocks.ts'
import * as Operations from './ticketStatisticsAgents.api.ts'
import * as ErrorTypes from '#shared/types/error.ts'

export function mockTicketStatisticsAgentsQuery(defaults: Mocks.MockDefaultsValue<Types.TicketStatisticsAgentsQuery, Types.TicketStatisticsAgentsQueryVariables>) {
  return Mocks.mockGraphQLResult(Operations.TicketStatisticsAgentsDocument, defaults)
}

export function waitForTicketStatisticsAgentsQueryCalls() {
  return Mocks.waitForGraphQLMockCalls<Types.TicketStatisticsAgentsQuery>(Operations.TicketStatisticsAgentsDocument)
}

export function mockTicketStatisticsAgentsQueryError(message: string, extensions: {type: ErrorTypes.GraphQLErrorTypes }) {
  return Mocks.mockGraphQLResultWithError(Operations.TicketStatisticsAgentsDocument, message, extensions);
}
