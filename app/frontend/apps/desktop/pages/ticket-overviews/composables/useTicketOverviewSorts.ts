// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// Odice : tri sur plusieurs colonnes des vues de tickets.
//
// Chaque clic sur un en-tête fait passer la colonne par croissant → décroissant
// → sans tri. Le premier tri posé reste le critère principal ; les suivants ne
// départagent que les ex aequo. Sans tri choisi, la vue garde son ordre défini.
//
// Comme les filtres, les tris sont propres à chaque vue et vivent le temps de
// l'onglet (sessionStorage).

import { useSessionStorage } from '@vueuse/core'
import { computed, type MaybeRefOrGetter, toValue } from 'vue'

import type { TicketOverviewSortInput } from '#shared/graphql/types.ts'

import type { TableSort } from '#desktop/components/CommonTable/types.ts'

const storage = useSessionStorage<Record<string, TableSort[]>>('odice-ticket-overview-sorts', {})

export const useTicketOverviewSorts = (overviewId: MaybeRefOrGetter<string>) => {
  const sorts = computed<TableSort[]>(() => storage.value[toValue(overviewId)] ?? [])

  const setSorts = (newSorts: TableSort[]) => {
    const next = { ...storage.value }

    if (newSorts.length) next[toValue(overviewId)] = newSorts
    else delete next[toValue(overviewId)]

    storage.value = next
  }

  // Ce qui part au serveur ; `undefined` sans tri, pour ne pas multiplier les
  // entrées de cache inutilement.
  const querySorts = computed<TicketOverviewSortInput[] | undefined>(() =>
    sorts.value.length
      ? sorts.value.map(({ column, direction }) => ({ column, direction }))
      : undefined,
  )

  return { sorts, querySorts, setSorts }
}
