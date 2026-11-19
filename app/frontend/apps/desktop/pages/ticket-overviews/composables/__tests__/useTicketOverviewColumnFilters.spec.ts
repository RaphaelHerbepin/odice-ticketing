// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { ref } from 'vue'

import { EnumTicketOverviewColumnFilterOperator } from '#shared/graphql/types.ts'

import type { TableAttribute } from '#desktop/components/CommonTable/types.ts'

import {
  isColumnFilterable,
  useTicketOverviewColumnFilters,
} from '../useTicketOverviewColumnFilters.ts'

const attribute = (
  name: string,
  dataType: string,
  dataOption: Record<string, unknown> = {},
): TableAttribute => ({ name, label: name, dataType, dataOption }) as TableAttribute

describe('useTicketOverviewColumnFilters', () => {
  beforeEach(() => {
    useTicketOverviewColumnFilters('1').clearFilters()
    useTicketOverviewColumnFilters('2').clearFilters()
  })

  it('keeps one filter per column and sends a stable, label-free list', () => {
    const { applyFilter, filters, queryFilters } = useTicketOverviewColumnFilters('1')

    expect(queryFilters.value).toBeUndefined()

    applyFilter({
      column: 'title',
      label: 'Title',
      operator: EnumTicketOverviewColumnFilterOperator.Contains,
      value: 'claude',
    })
    applyFilter({
      column: 'customer_id',
      label: 'Customer',
      operator: EnumTicketOverviewColumnFilterOperator.StartsWith,
      value: 'lau',
    })
    applyFilter({
      column: 'title',
      label: 'Title',
      operator: EnumTicketOverviewColumnFilterOperator.IsEmpty,
      value: 'ignored',
    })

    expect(filters.value).toHaveLength(2)
    expect(queryFilters.value).toEqual([
      {
        column: 'customer_id',
        operator: EnumTicketOverviewColumnFilterOperator.StartsWith,
        value: 'lau',
      },
      {
        column: 'title',
        operator: EnumTicketOverviewColumnFilterOperator.IsEmpty,
        value: undefined,
      },
    ])
  })

  it('isolates filters per overview and follows the current overview', () => {
    const overviewId = ref('1')
    const current = useTicketOverviewColumnFilters(overviewId)

    current.applyFilter({
      column: 'title',
      label: 'Title',
      operator: EnumTicketOverviewColumnFilterOperator.Contains,
      value: 'x',
    })

    overviewId.value = '2'
    expect(current.filters.value).toEqual([])

    overviewId.value = '1'
    expect(current.filterForColumn('title')?.value).toBe('x')

    current.removeFilter('title')
    expect(current.filters.value).toEqual([])
  })
})

describe('isColumnFilterable', () => {
  it('accepts text-like columns and known relations', () => {
    expect(isColumnFilterable(attribute('title', 'input'))).toBe(true)
    expect(isColumnFilterable(attribute('customer_id', 'user_autocompletion'))).toBe(true)
    expect(isColumnFilterable(attribute('objet_demande', 'tree_select'))).toBe(true)
    expect(isColumnFilterable(attribute('agence', 'select'))).toBe(true)
  })

  it('rejects dates, icons and unknown relations', () => {
    expect(isColumnFilterable(attribute('updated_at', 'datetime'))).toBe(false)
    expect(isColumnFilterable(attribute('stateIcon', 'icon'))).toBe(false)
    expect(isColumnFilterable(attribute('other_id', 'select', { relation: 'User' }))).toBe(false)
  })
})
