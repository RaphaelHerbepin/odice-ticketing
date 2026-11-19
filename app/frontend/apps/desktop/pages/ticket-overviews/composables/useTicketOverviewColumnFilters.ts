// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// Odice : filtres par colonne des vues de tickets.
//
// Un filtre par colonne au plus ; ils se cumulent entre colonnes (ET). Ils
// vivent dans le sessionStorage, par vue : ils survivent au passage par un
// ticket et au rechargement de la page, mais pas à la fermeture de l'onglet —
// une vue qui paraîtrait « vide » le lendemain à cause d'un filtre oublié
// serait pire que de devoir le reposer.

import { useSessionStorage } from '@vueuse/core'
import { computed, type MaybeRefOrGetter, toValue } from 'vue'

import {
  EnumTicketOverviewColumnFilterOperator,
  type TicketOverviewColumnFilterInput,
} from '#shared/graphql/types.ts'

import type { TableAttribute } from '#desktop/components/CommonTable/types.ts'

export interface TicketOverviewColumnFilter extends TicketOverviewColumnFilterInput {
  /** Libellé de la colonne, pour l'afficher dans la barre des filtres. */
  label: string
}

export const columnFilterOperators: {
  value: EnumTicketOverviewColumnFilterOperator
  label: string
  needsValue: boolean
}[] = [
  {
    value: EnumTicketOverviewColumnFilterOperator.Contains,
    label: __('contains'),
    needsValue: true,
  },
  {
    value: EnumTicketOverviewColumnFilterOperator.NotContains,
    label: __('does not contain'),
    needsValue: true,
  },
  {
    value: EnumTicketOverviewColumnFilterOperator.StartsWith,
    label: __('starts with'),
    needsValue: true,
  },
  {
    value: EnumTicketOverviewColumnFilterOperator.EndsWith,
    label: __('ends with'),
    needsValue: true,
  },
  {
    value: EnumTicketOverviewColumnFilterOperator.Equals,
    label: __('is equal to'),
    needsValue: true,
  },
  {
    value: EnumTicketOverviewColumnFilterOperator.NotEquals,
    label: __('is not equal to'),
    needsValue: true,
  },
  {
    value: EnumTicketOverviewColumnFilterOperator.IsEmpty,
    label: __('is empty'),
    needsValue: false,
  },
  {
    value: EnumTicketOverviewColumnFilterOperator.IsNotEmpty,
    label: __('is not empty'),
    needsValue: false,
  },
]

export const columnFilterOperatorNeedsValue = (operator: EnumTicketOverviewColumnFilterOperator) =>
  columnFilterOperators.find((item) => item.value === operator)?.needsValue ?? true

// Colonnes dont le serveur sait reconstituer la valeur affichée
// (voir Ticket::Overviews::ColumnFilter).
const FILTERABLE_COLUMNS = new Set([
  'title',
  'number',
  'customer_id',
  'owner_id',
  'organization_id',
  'group_id',
  'state_id',
  'priority_id',
  'created_by_id',
  'updated_by_id',
])

const FILTERABLE_DATA_TYPES = new Set(['input', 'textarea', 'richtext', 'select', 'tree_select'])

export const isColumnFilterable = (attribute: TableAttribute) => {
  if (FILTERABLE_COLUMNS.has(attribute.name)) return true

  return (
    FILTERABLE_DATA_TYPES.has(attribute.dataType) &&
    !(attribute.dataOption as Record<string, unknown> | undefined)?.relation
  )
}

const storage = useSessionStorage<Record<string, TicketOverviewColumnFilter[]>>(
  'odice-ticket-overview-column-filters',
  {},
)

export const useTicketOverviewColumnFilters = (overviewId: MaybeRefOrGetter<string>) => {
  const filters = computed<TicketOverviewColumnFilter[]>(
    () => storage.value[toValue(overviewId)] ?? [],
  )

  const setFilters = (newFilters: TicketOverviewColumnFilter[]) => {
    const next = { ...storage.value }

    if (newFilters.length) next[toValue(overviewId)] = newFilters
    else delete next[toValue(overviewId)]

    storage.value = next
  }

  const filterForColumn = (column: string) => filters.value.find((item) => item.column === column)

  const applyFilter = (filter: TicketOverviewColumnFilter) => {
    const others = filters.value.filter((item) => item.column !== filter.column)

    setFilters([...others, filter])
  }

  const removeFilter = (column: string) =>
    setFilters(filters.value.filter((item) => item.column !== column))

  const clearFilters = () => setFilters([])

  // Ce que reçoit le serveur : sans le libellé, et dans un ordre stable pour
  // que les clés de cache ne dépendent pas de l'ordre de saisie.
  const queryFilters = computed<TicketOverviewColumnFilterInput[] | undefined>(() => {
    if (!filters.value.length) return undefined

    return filters.value
      .map(({ column, operator, value }) => ({
        column,
        operator,
        value: columnFilterOperatorNeedsValue(operator) ? value : undefined,
      }))
      .sort((a, b) => a.column.localeCompare(b.column))
  })

  return {
    filters,
    queryFilters,
    filterForColumn,
    applyFilter,
    removeFilter,
    clearFilters,
  }
}
