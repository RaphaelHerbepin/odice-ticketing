<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import { useLocaleStore } from '#shared/stores/locale.ts'

import LayoutContent from '#desktop/components/layout/LayoutContent.vue'
import StatisticsChart from '#desktop/pages/statistics/components/StatisticsChart.vue'
import StatisticsPanel from '#desktop/pages/statistics/components/StatisticsPanel.vue'
import StatisticsToolbar from '#desktop/pages/statistics/components/StatisticsToolbar.vue'
import { useStatisticsAxes } from '#desktop/pages/statistics/composables/useStatisticsAxes.ts'
import {
  accentColor,
  barOption,
  timeSeriesOption,
} from '#desktop/pages/statistics/composables/useStatisticsChart.ts'
import { useStatisticsFilters } from '#desktop/pages/statistics/composables/useStatisticsFilters.ts'
import { useStatisticsFormat } from '#desktop/pages/statistics/composables/useStatisticsFormat.ts'
import { useStatisticsPeriod } from '#desktop/pages/statistics/composables/useStatisticsPeriod.ts'
import { useStatisticsTabs } from '#desktop/pages/statistics/composables/useStatisticsTabs.ts'
import { useTicketStatisticsQuery } from '#desktop/pages/statistics/graphql/queries/ticketStatistics.api.ts'

const { tabs, activeTab } = useStatisticsTabs()
const { seriesVariables } = useStatisticsPeriod()
const { axes } = useStatisticsAxes()
const { filterVariables } = useStatisticsFilters(axes)
const { formatNumber, formatDuration, formatPercent } = useStatisticsFormat()
const locale = useLocaleStore()

const queryVariables = computed(() => ({ ...seriesVariables.value, ...filterVariables.value }))

const { result, loading } = useTicketStatisticsQuery(queryVariables)
const statistics = computed(() => result.value?.ticketStatistics)
const totals = computed(() => statistics.value?.totals)

const headline = computed(() => [
  { key: 'total', label: __('Tickets created'), value: formatNumber(totals.value?.total) },
  { key: 'open', label: __('Still open'), value: formatNumber(totals.value?.open) },
  { key: 'closed', label: __('Closed'), value: formatNumber(totals.value?.closed) },
  { key: 'escalated', label: __('Escalated'), value: formatNumber(totals.value?.escalated) },
  {
    key: 'first',
    label: __('Average first response'),
    value: formatDuration(totals.value?.averageFirstResponseMinutes),
  },
  {
    key: 'close',
    label: __('Average time to close'),
    value: formatDuration(totals.value?.averageCloseMinutes),
  },
  {
    key: 'firstPct',
    label: __('First response in time'),
    value: formatPercent(totals.value?.firstResponseInTimePercent),
  },
  {
    key: 'closePct',
    label: __('Closed in time'),
    value: formatPercent(totals.value?.closeInTimePercent),
  },
])

/* La saisie du temps étant facultative, le total seul laisserait croire qu'il
   mesure l'effort alors qu'il ne mesure que la part déclarée. Sous 50 % de
   couverture, c'est le taux qui devient l'information principale : « on ne sait
   pas encore » est la réponse exacte, et la donner évite une décision fondée
   sur un chiffre incomplet. */
const coverage = computed(() => totals.value?.timeCoveragePercent)
const timeCard = computed(() => {
  if (coverage.value === null || coverage.value === undefined) return null
  const weak = coverage.value < 50
  return {
    value: weak ? formatPercent(coverage.value) : formatDuration(totals.value?.timeLoggedMinutes),
    label: weak ? __('Time logging coverage') : __('Time logged'),
    hint: weak
      ? __('Too few tickets carry a time entry for the total to mean anything yet.')
      : `${formatPercent(coverage.value)} ${__('of tickets')}`,
  }
})

/* Le pas est celui que le serveur a réellement appliqué, et non celui demandé :
   en mode automatique, seul lui le connaît. */
const appliedInterval = computed(() => statistics.value?.period?.interval ?? 'day')

const volumeOption = computed(() =>
  timeSeriesOption(
    statistics.value?.volumeOverTime ?? [],
    appliedInterval.value,
    locale.localeData?.locale,
  ),
)

/* Six répartitions, et non trois. Les trois premières décrivent la NATURE des
   demandes, les trois suivantes leur RÉPARTITION dans l'organisation — deux
   questions distinctes, que la page traitait à moitié. */
const breakdowns = computed(() => [
  { key: 'state', title: __('By state'), buckets: statistics.value?.byState ?? [] },
  { key: 'priority', title: __('By priority'), buckets: statistics.value?.byPriority ?? [] },
  { key: 'channel', title: __('By channel'), buckets: statistics.value?.byChannel ?? [] },
  { key: 'group', title: __('By service'), buckets: statistics.value?.byGroup ?? [], accent: true },
  { key: 'owner', title: __('By agent'), buckets: statistics.value?.byOwner ?? [], accent: true },
  {
    key: 'organization',
    title: __('By organization'),
    buckets: statistics.value?.byOrganization ?? [],
    accent: true,
  },
])
</script>

<template>
  <LayoutContent
    :breadcrumb-items="[{ label: __('Statistics') }]"
    :tabs="tabs"
    :active-tab="activeTab"
    width="full"
  >
    <div class="flex flex-col gap-6 p-4">
      <StatisticsToolbar show-interval />

      <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
        <div
          v-for="item in headline"
          :key="item.key"
          class="rounded-lg border border-neutral-100 bg-neutral-50 p-4 dark:border-gray-900 dark:bg-gray-500"
        >
          <div class="text-xs text-stone-200 dark:text-neutral-500">{{ $t(item.label) }}</div>
          <div class="mt-1 text-2xl font-semibold text-gray-100 dark:text-neutral-400">
            {{ item.value }}
          </div>
        </div>

        <div
          v-if="timeCard"
          class="rounded-lg border border-neutral-100 bg-neutral-50 p-4 dark:border-gray-900 dark:bg-gray-500"
        >
          <div class="text-xs text-stone-200 dark:text-neutral-500">{{ $t(timeCard.label) }}</div>
          <div class="mt-1 text-2xl font-semibold text-gray-100 dark:text-neutral-400">
            {{ timeCard.value }}
          </div>
          <div class="mt-1 text-xs text-stone-200 dark:text-neutral-500">
            {{ $t(timeCard.hint) }}
          </div>
        </div>
      </div>

      <StatisticsPanel
        :title="$t('Created and closed over time')"
        :has-data="!!statistics?.volumeOverTime?.length"
        :loading="loading"
      >
        <div class="h-72 w-full"><StatisticsChart :option="volumeOption" /></div>
      </StatisticsPanel>

      <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <StatisticsPanel
          v-for="breakdown in breakdowns"
          :key="breakdown.key"
          :title="$t(breakdown.title)"
          :has-data="breakdown.buckets.length > 0"
          :loading="loading"
        >
          <div class="h-64 w-full">
            <StatisticsChart
              :option="barOption(breakdown.buckets, breakdown.accent ? accentColor : undefined)"
            />
          </div>
        </StatisticsPanel>
      </div>
    </div>
  </LayoutContent>
</template>
