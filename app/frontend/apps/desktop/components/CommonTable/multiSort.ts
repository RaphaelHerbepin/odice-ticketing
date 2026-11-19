// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { EnumOrderDirection } from '#shared/graphql/types.ts'

import type { TableSort } from './types.ts'

/**
 * Odice: next state of a multi-column sort after a click on `column`.
 *
 * Each column cycles ascending → descending → not sorted. A newly sorted column
 * is added at the end, so it only orders rows that the earlier columns leave
 * tied; changing direction keeps the column at its place in the priority order.
 */
export const cycleTableSort = (sorts: TableSort[], column: string): TableSort[] => {
  const current = sorts.find((sort) => sort.column === column)

  if (!current) return [...sorts, { column, direction: EnumOrderDirection.Ascending }]

  if (current.direction === EnumOrderDirection.Ascending)
    return sorts.map((sort) =>
      sort.column === column ? { column, direction: EnumOrderDirection.Descending } : sort,
    )

  return sorts.filter((sort) => sort.column !== column)
}
