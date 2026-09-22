<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, ref } from 'vue'

import { useLocaleStore } from '#shared/stores/locale.ts'

import CommonBarChart from '#desktop/components/CommonCharts/CommonBarChart/CommonBarChart.vue'
import type { BarChartOptions } from '#desktop/components/CommonCharts/CommonBarChart/types.ts'
import LayoutContent from '#desktop/components/layout/LayoutContent.vue'
import { useTicketStatisticsQuery } from '#desktop/pages/statistics/graphql/queries/ticketStatistics.api.ts'
import { useTicketStatisticsAgentsQuery } from '#desktop/pages/statistics/graphql/queries/ticketStatisticsAgents.api.ts'
import { useTicketStatisticsAxesQuery } from '#desktop/pages/statistics/graphql/queries/ticketStatisticsAxes.api.ts'

interface Bucket {
  label: string
  count: number
}

type AgentRow = NonNullable<
  ReturnType<typeof useTicketStatisticsAgentsQuery>['result']['value']
>['ticketStatisticsAgents'][number]

// Périodes proposées, en jours. La charte demande des libellés explicites
// plutôt que des abréviations.
const periods = [
  { days: 7, label: __('7 days') },
  { days: 30, label: __('30 days') },
  { days: 90, label: __('90 days') },
  { days: 365, label: __('12 months') },
]

const selectedDays = ref(30)

/* Les axes métier ne sont pas codés ici : le serveur les dérive des champs
   personnalisés réellement définis, et refuse tout nom hors de cette liste.
   Ajouter un champ dans l'administration suffit donc à le voir apparaître. */
const { result: axesResult } = useTicketStatisticsAxesQuery()
const availableAxes = computed(() => axesResult.value?.ticketStatisticsAxes ?? [])

const variables = computed(() => {
  const to = new Date()
  const from = new Date(to.getTime() - selectedDays.value * 24 * 60 * 60 * 1000)
  return {
    from: from.toISOString(),
    to: to.toISOString(),
    axes: availableAxes.value.map((axis) => axis.name),
  }
})

const { result, loading } = useTicketStatisticsQuery(variables)

const { result: agentsResult } = useTicketStatisticsAgentsQuery(() => ({
  from: variables.value.from,
  to: variables.value.to,
}))
const agents = computed(() => agentsResult.value?.ticketStatisticsAgents ?? [])

const statistics = computed(() => result.value?.ticketStatistics)
const totals = computed(() => statistics.value?.totals)

const locale = useLocaleStore()

const formatNumber = (value?: number | null) =>
  value === null || value === undefined
    ? '—'
    : new Intl.NumberFormat(locale.localeData?.locale).format(value)

/** Minutes -> durée lisible. Au-delà de 48 h on bascule en jours. */
const formatDuration = (minutes?: number | null) => {
  if (minutes === null || minutes === undefined) return '—'
  if (minutes < 60) return `${Math.round(minutes)} min`
  const hours = minutes / 60
  if (hours < 48) return `${hours.toFixed(1)} h`
  return `${(hours / 24).toFixed(1)} j`
}

const formatPercent = (value?: number | null) =>
  value === null || value === undefined ? '—' : `${value.toFixed(1)} %`

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

/* Les couleurs viennent des jetons de marque : le graphique suit donc
   automatiquement le thème clair/sombre et la charte. */
const brandColor = '#134c82'
const accentColor = '#27a9ce'

const barOption = (buckets: Bucket[] = [], color = brandColor): BarChartOptions => ({
  tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
  grid: { left: 8, right: 16, top: 16, bottom: 8, containLabel: true },
  xAxis: { type: 'value', minInterval: 1 },
  yAxis: {
    type: 'category',
    // ECharts empile les catégories du bas vers le haut : on inverse pour
    // que la valeur la plus élevée apparaisse en haut.
    data: [...buckets].reverse().map((bucket) => bucket.label),
  },
  series: [
    {
      type: 'bar',
      data: [...buckets].reverse().map((bucket) => bucket.count),
      itemStyle: { color, borderRadius: [0, 4, 4, 0] },
      barMaxWidth: 22,
    },
  ],
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
        stack: undefined,
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

/* Répartitions métier — agence, service, objet de la demande. Ce sont elles
   qui portent la lecture d'activité propre à Odice, d'où leur place avant les
   répartitions génériques de Zammad. */
const businessAxes = computed(() => statistics.value?.byAxis ?? [])

/* Colonnes du tableau par agent. Stock d'abord — c'est ce qu'on regarde en
   premier —, puis flux, puis délais. Le temps saisi ferme la marche : il est
   attribué à qui l'a saisi, pas au propriétaire du ticket, et ne doit donc pas
   être lu comme une mesure de la charge. */
const agentColumns = [
  { key: 'open', label: __('Open'), value: (a: AgentRow) => formatNumber(a.open) },
  { key: 'escalated', label: __('Escalated'), value: (a: AgentRow) => formatNumber(a.escalated) },
  { key: 'dormant', label: __('Dormant'), value: (a: AgentRow) => formatNumber(a.dormant) },
  { key: 'received', label: __('Received'), value: (a: AgentRow) => formatNumber(a.received) },
  { key: 'closed', label: __('Closed'), value: (a: AgentRow) => formatNumber(a.closed) },
  {
    key: 'first',
    label: __('Average first response'),
    value: (a: AgentRow) => formatDuration(a.averageFirstResponseMinutes),
  },
  {
    key: 'close',
    label: __('Average time to close'),
    value: (a: AgentRow) => formatDuration(a.averageCloseMinutes),
  },
  {
    key: 'inTime',
    label: __('Closed in time'),
    value: (a: AgentRow) => formatPercent(a.closeInTimePercent),
  },
  {
    key: 'time',
    label: __('Time logged'),
    value: (a: AgentRow) => formatDuration(a.timeLoggedMinutes),
  },
]

const breakdowns = computed(() => [
  { key: 'group', title: __('By service'), buckets: statistics.value?.byGroup ?? [] },
  {
    key: 'organization',
    title: __('By organization'),
    buckets: statistics.value?.byOrganization ?? [],
  },
  { key: 'state', title: __('By state'), buckets: statistics.value?.byState ?? [] },
  { key: 'priority', title: __('By priority'), buckets: statistics.value?.byPriority ?? [] },
  { key: 'owner', title: __('By agent'), buckets: statistics.value?.byOwner ?? [] },
  { key: 'channel', title: __('By channel'), buckets: statistics.value?.byChannel ?? [] },
])
</script>

<template>
  <LayoutContent :breadcrumb-items="[{ label: __('Statistics') }]" width="full">
    <div class="flex flex-col gap-6 p-4">
      <!-- Sélecteur de période -->
      <div class="flex flex-wrap items-center gap-2">
        <button
          v-for="period in periods"
          :key="period.days"
          type="button"
          class="rounded-md px-3 py-1.5 text-sm font-medium transition-colors"
          :class="
            selectedDays === period.days
              ? 'bg-blue-800 text-white'
              : 'bg-neutral-50 text-gray-100 hover:bg-blue-100 dark:bg-gray-500 dark:text-neutral-400'
          "
          @click="selectedDays = period.days"
        >
          {{ $t(period.label) }}
        </button>
      </div>

      <!-- Chiffres clés -->
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
      </div>

      <!-- Volume dans le temps -->
      <section
        class="rounded-lg border border-neutral-100 bg-neutral-50 p-4 dark:border-gray-900 dark:bg-gray-500"
      >
        <h2 class="mb-3 text-base font-semibold text-gray-100 dark:text-neutral-400">
          {{ $t('Created and closed over time') }}
        </h2>
        <div class="h-72 w-full">
          <CommonBarChart v-if="!loading" :option="volumeOption" />
        </div>
      </section>

      <!-- Par agent -->
      <section
        v-if="agents.length"
        class="rounded-lg border border-neutral-100 bg-neutral-50 p-4 dark:border-gray-900 dark:bg-gray-500"
      >
        <h2 class="text-base font-semibold text-gray-100 dark:text-neutral-400">
          {{ $t('By agent') }}
        </h2>
        <!-- Les trois premières colonnes sont un instantané : les afficher sans
             le dire laisserait croire qu'elles suivent la période choisie. -->
        <p class="mt-1 mb-3 text-xs text-stone-200 dark:text-neutral-500">
          {{ $t('Workload is a snapshot of the present; the other figures cover the selected period.') }}
        </p>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-neutral-100 text-left dark:border-gray-900">
                <th class="py-2 pe-3 font-medium text-stone-200 dark:text-neutral-500">
                  {{ $t('Agent') }}
                </th>
                <th
                  v-for="column in agentColumns"
                  :key="column.key"
                  class="py-2 pe-3 text-end font-medium text-stone-200 dark:text-neutral-500"
                >
                  {{ $t(column.label) }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="agent in agents"
                :key="agent.id"
                class="border-b border-neutral-100 last:border-0 dark:border-gray-900"
              >
                <td class="py-2 pe-3 text-gray-100 dark:text-neutral-400">{{ agent.label }}</td>
                <td
                  v-for="column in agentColumns"
                  :key="column.key"
                  class="py-2 pe-3 text-end text-gray-100 tabular-nums dark:text-neutral-400"
                >
                  {{ column.value(agent) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- Répartitions métier -->
      <div v-if="businessAxes.length" class="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <section
          v-for="axis in businessAxes"
          :key="axis.name"
          class="rounded-lg border border-neutral-100 bg-neutral-50 p-4 dark:border-gray-900 dark:bg-gray-500"
        >
          <h2 class="mb-3 text-base font-semibold text-gray-100 dark:text-neutral-400">
            {{ axis.label }}
          </h2>
          <div v-if="!loading && axis.buckets.length" class="h-64 w-full">
            <CommonBarChart :option="barOption(axis.buckets, accentColor)" />
          </div>
          <p v-else-if="!loading" class="text-sm text-stone-200 dark:text-neutral-500">
            {{ $t('No data for this period.') }}
          </p>
        </section>
      </div>

      <!-- Répartitions -->
      <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <section
          v-for="breakdown in breakdowns"
          :key="breakdown.key"
          class="rounded-lg border border-neutral-100 bg-neutral-50 p-4 dark:border-gray-900 dark:bg-gray-500"
        >
          <h2 class="mb-3 text-base font-semibold text-gray-100 dark:text-neutral-400">
            {{ $t(breakdown.title) }}
          </h2>
          <div v-if="!loading && breakdown.buckets.length" class="h-64 w-full">
            <CommonBarChart :option="barOption(breakdown.buckets)" />
          </div>
          <p v-else-if="!loading" class="text-sm text-stone-200 dark:text-neutral-500">
            {{ $t('No data for this period.') }}
          </p>
        </section>
      </div>
    </div>
  </LayoutContent>
</template>
