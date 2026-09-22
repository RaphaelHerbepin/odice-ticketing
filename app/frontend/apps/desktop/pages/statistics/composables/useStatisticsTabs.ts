// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { computed } from 'vue'
import { useRoute } from 'vue-router'

import type { NavigationTab } from '#desktop/components/CommonTabs/types.ts'

/**
 * Les trois onglets de la page Statistiques.
 *
 * La période voyage dans la query string : on la recopie dans les liens pour
 * qu'un changement d'onglet ne la réinitialise pas.
 */
export const useStatisticsTabs = () => {
  const route = useRoute()

  const query = computed(() => (route.query.days ? { days: route.query.days } : {}))

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
      key: 'agents',
      label: __('Agents'),
      link: { name: 'StatisticsAgents', query: query.value },
    },
  ])

  const activeTab = computed(() => {
    if (route.name === 'StatisticsAxes') return 'axes'
    if (route.name === 'StatisticsAgents') return 'agents'
    return 'overview'
  })

  return { tabs, activeTab }
}
