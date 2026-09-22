<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import { i18n } from '#shared/i18n/index.ts'
import { useLocaleStore } from '#shared/stores/locale.ts'

import LayoutContent from '#desktop/components/layout/LayoutContent.vue'
import StatisticsChart from '#desktop/pages/statistics/components/StatisticsChart.vue'
import StatisticsExportButton from '#desktop/pages/statistics/components/StatisticsExportButton.vue'
import StatisticsPanel from '#desktop/pages/statistics/components/StatisticsPanel.vue'
import StatisticsToolbar from '#desktop/pages/statistics/components/StatisticsToolbar.vue'
import StatisticsTrend from '#desktop/pages/statistics/components/StatisticsTrend.vue'
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
import { computeTrend } from '#desktop/pages/statistics/composables/useStatisticsTrend.ts'
import { useTicketStatisticsQuery } from '#desktop/pages/statistics/graphql/queries/ticketStatistics.api.ts'

const { tabs, activeTab } = useStatisticsTabs()
const { seriesVariables } = useStatisticsPeriod()
const { axes } = useStatisticsAxes()
const { filterVariables } = useStatisticsFilters(axes)
const { formatNumber, formatDuration, formatPercent } = useStatisticsFormat()
const locale = useLocaleStore()

const queryVariables = computed(() => ({
  ...seriesVariables.value,
  ...filterVariables.value,
  compare: true,
}))

const { result, loading } = useTicketStatisticsQuery(queryVariables)
const statistics = computed(() => result.value?.ticketStatistics)
const totals = computed(() => statistics.value?.totals)

const comparison = computed(() => statistics.value?.comparison)

/* Le libellé de la période de référence vient des bornes que le SERVEUR a
   réellement interrogées. Les recalculer ici les placerait à quelques secondes
   près, et la carte nommerait une période qui n'est pas celle mesurée. */
const periodLabel = computed(() => {
  if (!comparison.value) return ''
  const from = new Date(comparison.value.from)
  const to = new Date(comparison.value.to)
  const format = new Intl.DateTimeFormat(locale.localeData?.locale, {
    day: '2-digit',
    month: '2-digit',
  })
  return `${i18n.t('vs')} ${format.format(from)} – ${format.format(to)}`
})

/* Le sens de lecture vit ici, à côté du libellé et du formateur de chaque
   métrique : c'est une propriété de la grandeur, identique sur toute
   instance. Le porter côté serveur imposerait d'inventer une API de
   descripteurs plus grosse que la fonctionnalité.

   `open`, `closed` et `escalated` n'ont volontairement pas d'évolution : ce
   sont des états observés aujourd'hui sur une cohorte de création, et le
   serveur refuse d'ailleurs de les comparer. */
const headline = computed(() => [
  {
    key: 'total',
    label: __('Tickets created'),
    value: formatNumber(totals.value?.total),
    trend: computeTrend(totals.value?.total, comparison.value?.total, {
      direction: 'neutral',
      unit: 'count',
    }),
  },
  { key: 'open', label: __('Still open'), value: formatNumber(totals.value?.open), trend: null },
  { key: 'closed', label: __('Closed'), value: formatNumber(totals.value?.closed), trend: null },
  {
    key: 'escalated',
    label: __('Escalated'),
    value: formatNumber(totals.value?.escalated),
    trend: null,
  },
  {
    key: 'first',
    label: __('Average first response'),
    value: formatDuration(totals.value?.averageFirstResponseMinutes),
    trend: computeTrend(
      totals.value?.averageFirstResponseMinutes,
      comparison.value?.averageFirstResponseMinutes,
      { direction: 'down-is-good', unit: 'duration' },
    ),
  },
  {
    key: 'close',
    label: __('Average time to close'),
    value: formatDuration(totals.value?.averageCloseMinutes),
    trend: computeTrend(totals.value?.averageCloseMinutes, comparison.value?.averageCloseMinutes, {
      direction: 'down-is-good',
      unit: 'duration',
    }),
  },
  {
    key: 'firstPct',
    label: __('First response in time'),
    value: formatPercent(totals.value?.firstResponseInTimePercent),
    trend: computeTrend(
      totals.value?.firstResponseInTimePercent,
      comparison.value?.firstResponseInTimePercent,
      { direction: 'up-is-good', unit: 'percent' },
    ),
  },
  {
    key: 'closePct',
    label: __('Closed in time'),
    value: formatPercent(totals.value?.closeInTimePercent),
    trend: computeTrend(totals.value?.closeInTimePercent, comparison.value?.closeInTimePercent, {
      direction: 'up-is-good',
      unit: 'percent',
    }),
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
    <template #headerRight>
      <StatisticsExportButton />
    </template>

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
          <StatisticsTrend :trend="item.trend" :period-label="periodLabel" />
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
