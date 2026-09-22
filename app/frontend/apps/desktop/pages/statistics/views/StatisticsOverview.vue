<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import CommonBarChart from '#desktop/components/CommonCharts/CommonBarChart/CommonBarChart.vue'
import type { BarChartOptions } from '#desktop/components/CommonCharts/CommonBarChart/types.ts'
import LayoutContent from '#desktop/components/layout/LayoutContent.vue'
import StatisticsPanel from '#desktop/pages/statistics/components/StatisticsPanel.vue'
import StatisticsPeriodFilter from '#desktop/pages/statistics/components/StatisticsPeriodFilter.vue'
import {
  accentColor,
  barOption,
  brandColor,
} from '#desktop/pages/statistics/composables/useStatisticsChart.ts'
import { useStatisticsFormat } from '#desktop/pages/statistics/composables/useStatisticsFormat.ts'
import { useStatisticsPeriod } from '#desktop/pages/statistics/composables/useStatisticsPeriod.ts'
import { useStatisticsTabs } from '#desktop/pages/statistics/composables/useStatisticsTabs.ts'
import { useTicketStatisticsQuery } from '#desktop/pages/statistics/graphql/queries/ticketStatistics.api.ts'

const { tabs, activeTab } = useStatisticsTabs()
const { variables } = useStatisticsPeriod()
const { formatNumber, formatDuration, formatPercent } = useStatisticsFormat()

const { result, loading } = useTicketStatisticsQuery(variables)
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

const volumeOption = computed<BarChartOptions>(() => {
  const points = statistics.value?.volumeOverTime ?? []
  return {
    tooltip: { trigger: 'axis' },
    legend: { top: 0 },
    grid: { left: 8, right: 16, top: 40, bottom: 8, containLabel: true },
    xAxis: { type: 'category', data: points.map((point) => point.date) },
    yAxis: { type: 'value', minInterval: 1 },
    series: [
      {
        name: __('Created'),
        type: 'bar',
        data: points.map((point) => point.created),
        itemStyle: { color: brandColor, borderRadius: [3, 3, 0, 0] },
      },
      {
        name: __('Closed'),
        type: 'bar',
        data: points.map((point) => point.closed),
        itemStyle: { color: accentColor, borderRadius: [3, 3, 0, 0] },
      },
    ],
  }
})

const breakdowns = computed(() => [
  { key: 'state', title: __('By state'), buckets: statistics.value?.byState ?? [] },
  { key: 'priority', title: __('By priority'), buckets: statistics.value?.byPriority ?? [] },
  { key: 'channel', title: __('By channel'), buckets: statistics.value?.byChannel ?? [] },
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
      <StatisticsPeriodFilter />

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
        <div class="h-72 w-full"><CommonBarChart :option="volumeOption" /></div>
      </StatisticsPanel>

      <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <StatisticsPanel
          v-for="breakdown in breakdowns"
          :key="breakdown.key"
          :title="$t(breakdown.title)"
          :has-data="breakdown.buckets.length > 0"
          :loading="loading"
        >
          <div class="h-64 w-full"><CommonBarChart :option="barOption(breakdown.buckets)" /></div>
        </StatisticsPanel>
      </div>
    </div>
  </LayoutContent>
</template>
