import * as Types from '#shared/graphql/types.ts';

import * as Mocks from '#tests/graphql/builders/mocks.ts'
import * as Operations from './ticketStatistics.api.ts'
import * as ErrorTypes from '#shared/types/error.ts'

export function mockTicketStatisticsQuery(defaults: Mocks.MockDefaultsValue<Types.TicketStatisticsQuery, Types.TicketStatisticsQueryVariables>) {
  return Mocks.mockGraphQLResult(Operations.TicketStatisticsDocument, defaults)
}

export function waitForTicketStatisticsQueryCalls() {
  return Mocks.waitForGraphQLMockCalls<Types.TicketStatisticsQuery>(Operations.TicketStatisticsDocument)
}

export function mockTicketStatisticsQueryError(message: string, extensions: {type: ErrorTypes.GraphQLErrorTypes }) {
  return Mocks.mockGraphQLResultWithError(Operations.TicketStatisticsDocument, message, extensions);
}
