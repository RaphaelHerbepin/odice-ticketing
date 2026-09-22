// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { computed } from 'vue'
import { useRoute } from 'vue-router'

import type { NavigationTab } from '#desktop/components/CommonTabs/types.ts'

/**
 * Les quatre onglets de la page Statistiques.
 *
 * La période voyage dans la query string : on la recopie dans les liens pour
 * qu'un changement d'onglet ne la réinitialise pas.
 */
export const useStatisticsTabs = () => {
  const route = useRoute()

  /* Toute la query string, et non les seules clés connues au moment d'écrire
     ces lignes : le pas de temps a été ajouté à l'URL sans l'être ici, et
     changer d'onglet le remettait silencieusement sur automatique. Chaque
     réglage futur — filtres, axes croisés — tomberait dans le même trou. */
  const query = computed(() => ({ ...route.query }))

  const tabs = computed<NavigationTab[]>(() => [
    {
      key: 'overview',
      label: __('Overview'),
      link: { name: 'StatisticsOverview', query: query.value },
    },
    {
      key: 'axes',
      label: __('Business axes'),
      link: { name: 'StatisticsAxes', query: query.value },
    },
    {
      key: 'cross',
      label: __('Cross-tabulation'),
      link: { name: 'StatisticsCross', query: query.value },
    },
    {
      key: 'agents',
      label: __('Agents'),
      link: { name: 'StatisticsAgents', query: query.value },
    },
  ])

  const activeTab = computed(() => {
    if (route.name === 'StatisticsAxes') return 'axes'
    if (route.name === 'StatisticsCross') return 'cross'
    if (route.name === 'StatisticsAgents') return 'agents'
    return 'overview'
  })

  return { tabs, activeTab }
}
