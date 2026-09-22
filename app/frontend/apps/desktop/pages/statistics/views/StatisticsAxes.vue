<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import LayoutContent from '#desktop/components/layout/LayoutContent.vue'
import StatisticsChart from '#desktop/pages/statistics/components/StatisticsChart.vue'
import StatisticsPanel from '#desktop/pages/statistics/components/StatisticsPanel.vue'
import StatisticsPeriodFilter from '#desktop/pages/statistics/components/StatisticsPeriodFilter.vue'
import { accentColor, barOption } from '#desktop/pages/statistics/composables/useStatisticsChart.ts'
import { useStatisticsPeriod } from '#desktop/pages/statistics/composables/useStatisticsPeriod.ts'
import { useStatisticsTabs } from '#desktop/pages/statistics/composables/useStatisticsTabs.ts'
import { useTicketStatisticsQuery } from '#desktop/pages/statistics/graphql/queries/ticketStatistics.api.ts'
import { useTicketStatisticsAxesQuery } from '#desktop/pages/statistics/graphql/queries/ticketStatisticsAxes.api.ts'

const { tabs, activeTab } = useStatisticsTabs()
const { variables } = useStatisticsPeriod()

/* Les axes ne sont pas listés ici : le serveur les dérive des champs
   personnalisés réellement définis. Ajouter un champ dans l'administration
   suffit donc à le voir apparaître, sans toucher au code. */
const { result: axesResult } = useTicketStatisticsAxesQuery()
const availableAxes = computed(() => axesResult.value?.ticketStatisticsAxes ?? [])

const queryVariables = computed(() => ({
  ...variables.value,
  axes: availableAxes.value.map((axis) => axis.name),
}))

const { result, loading } = useTicketStatisticsQuery(queryVariables)

/* Les axes renseignés d'abord. Un champ personnalisé n'est rempli que sur les
   formulaires qui le portent : sur une instance qui en compte une dizaine, la
   moitié est vide à tout instant, et les laisser dans l'ordre alphabétique
   mettait des cadres vides en tête de page. Les vides restent affichés — leur
   absence donnerait à croire que l'axe n'existe pas. */
const businessAxes = computed(() =>
  [...(result.value?.ticketStatistics?.byAxis ?? [])].sort(
    (a, b) => b.buckets.length - a.buckets.length,
  ),
)
</script>

<template>
  <LayoutContent
    :breadcrumb-items="[{ label: __('Statistics') }, { label: __('Business axes') }]"
    :tabs="tabs"
    :active-tab="activeTab"
    width="full"
  >
    <div class="flex flex-col gap-6 p-4">
      <StatisticsPeriodFilter />

      <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <StatisticsPanel
          v-for="axis in businessAxes"
          :key="axis.name"
          :title="axis.label"
          :has-data="axis.buckets.length > 0"
          :loading="loading"
        >
          <div class="h-64 w-full">
            <StatisticsChart :option="barOption(axis.buckets, accentColor)" />
          </div>
        </StatisticsPanel>
      </div>
    </div>
  </LayoutContent>
</template>
