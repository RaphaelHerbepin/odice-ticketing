// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { EnumOrderDirection } from '#shared/graphql/types.ts'

import { cycleTableSort } from '../multiSort.ts'

const { Ascending, Descending } = EnumOrderDirection

describe('cycleTableSort', () => {
  it('cycles a column through ascending, descending and no sorting', () => {
    const first = cycleTableSort([], 'customer_id')
    expect(first).toEqual([{ column: 'customer_id', direction: Ascending }])

    const second = cycleTableSort(first, 'customer_id')
    expect(second).toEqual([{ column: 'customer_id', direction: Descending }])

    expect(cycleTableSort(second, 'customer_id')).toEqual([])
  })

  it('adds new columns after the existing ones and keeps the priority order', () => {
    let sorts = cycleTableSort([], 'customer_id')
    sorts = cycleTableSort(sorts, 'customer_id')
    sorts = cycleTableSort(sorts, 'created_at')

    expect(sorts).toEqual([
      { column: 'customer_id', direction: Descending },
      { column: 'created_at', direction: Ascending },
    ])

    // Changing the direction of the secondary column keeps it secondary.
    sorts = cycleTableSort(sorts, 'created_at')
    expect(sorts.map((sort) => sort.column)).toEqual(['customer_id', 'created_at'])

    // Removing the primary column promotes the next one.
    sorts = cycleTableSort(cycleTableSort(sorts, 'customer_id'), 'customer_id')
    expect(sorts).toEqual([
      { column: 'created_at', direction: Descending },
      { column: 'customer_id', direction: Ascending },
    ])
  })
})
