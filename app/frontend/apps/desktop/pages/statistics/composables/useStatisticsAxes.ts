// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { computed } from 'vue'

import type { AxisDefinition } from '#desktop/pages/statistics/composables/useStatisticsFilters.ts'
import { useTicketStatisticsAxesQuery } from '#desktop/pages/statistics/graphql/queries/ticketStatisticsAxes.api.ts'

/**
 * Le catalogue des axes métier.
 *
 * Il ne dépend ni de la période ni des filtres : le serveur le dérive des
 * champs personnalisés réellement définis. Ajouter un champ dans
 * l'administration suffit donc à le voir apparaître, sans toucher au code.
 *
 * Plusieurs composants le réclament sur une même page — la barre de filtres et
 * la vue des axes. Apollo dédoublonne la requête, la réponse étant identique et
 * sans variable.
 */
export const useStatisticsAxes = () => {
  const { result, loading } = useTicketStatisticsAxesQuery()

  const axes = computed<AxisDefinition[]>(() =>
    (result.value?.ticketStatisticsAxes ?? []).map((axis) => ({
      name: axis.name,
      label: axis.label,
      values: axis.values.map((value) => ({ value: value.value, label: value.label })),
    })),
  )

  return { axes, loading }
}
