import * as Types from '#shared/graphql/types.ts';

import * as Mocks from '#tests/graphql/builders/mocks.ts'
import * as Operations from './ticketStatisticsCrosstab.api.ts'
import * as ErrorTypes from '#shared/types/error.ts'

export function mockTicketStatisticsCrosstabQuery(defaults: Mocks.MockDefaultsValue<Types.TicketStatisticsCrosstabQuery, Types.TicketStatisticsCrosstabQueryVariables>) {
  return Mocks.mockGraphQLResult(Operations.TicketStatisticsCrosstabDocument, defaults)
}

export function waitForTicketStatisticsCrosstabQueryCalls() {
  return Mocks.waitForGraphQLMockCalls<Types.TicketStatisticsCrosstabQuery>(Operations.TicketStatisticsCrosstabDocument)
}

export function mockTicketStatisticsCrosstabQueryError(message: string, extensions: {type: ErrorTypes.GraphQLErrorTypes }) {
  return Mocks.mockGraphQLResultWithError(Operations.TicketStatisticsCrosstabDocument, message, extensions);
}
