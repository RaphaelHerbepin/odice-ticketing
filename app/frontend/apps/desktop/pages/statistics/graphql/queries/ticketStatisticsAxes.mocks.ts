import * as Types from '#shared/graphql/types.ts';

import * as Mocks from '#tests/graphql/builders/mocks.ts'
import * as Operations from './ticketStatisticsAxes.api.ts'
import * as ErrorTypes from '#shared/types/error.ts'

export function mockTicketStatisticsAxesQuery(defaults: Mocks.MockDefaultsValue<Types.TicketStatisticsAxesQuery, Types.TicketStatisticsAxesQueryVariables>) {
  return Mocks.mockGraphQLResult(Operations.TicketStatisticsAxesDocument, defaults)
}

export function waitForTicketStatisticsAxesQueryCalls() {
  return Mocks.waitForGraphQLMockCalls<Types.TicketStatisticsAxesQuery>(Operations.TicketStatisticsAxesDocument)
}

export function mockTicketStatisticsAxesQueryError(message: string, extensions: {type: ErrorTypes.GraphQLErrorTypes }) {
  return Mocks.mockGraphQLResultWithError(Operations.TicketStatisticsAxesDocument, message, extensions);
}
