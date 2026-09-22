<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import LayoutContent from '#desktop/components/layout/LayoutContent.vue'
import StatisticsPanel from '#desktop/pages/statistics/components/StatisticsPanel.vue'
import StatisticsPeriodFilter from '#desktop/pages/statistics/components/StatisticsPeriodFilter.vue'
import { useStatisticsFormat } from '#desktop/pages/statistics/composables/useStatisticsFormat.ts'
import { useStatisticsPeriod } from '#desktop/pages/statistics/composables/useStatisticsPeriod.ts'
import { useStatisticsTabs } from '#desktop/pages/statistics/composables/useStatisticsTabs.ts'
import { useTicketStatisticsAgentsQuery } from '#desktop/pages/statistics/graphql/queries/ticketStatisticsAgents.api.ts'

const { tabs, activeTab } = useStatisticsTabs()
const { variables } = useStatisticsPeriod()
const { formatNumber, formatDuration, formatPercent } = useStatisticsFormat()

const { result, loading } = useTicketStatisticsAgentsQuery(variables)
const agents = computed(() => result.value?.ticketStatisticsAgents ?? [])

type AgentRow = (typeof agents.value)[number]

/* Trois familles, dans cet ordre : la charge — ce qu'on regarde en premier —,
   puis le flux, puis les délais. Le temps saisi ferme la marche : il est
   attribué à qui l'a saisi, pas au propriétaire du ticket, et ne se lit donc
   pas comme une mesure de la charge. */
const columns = [
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
</script>

<template>
  <LayoutContent
    :breadcrumb-items="[{ label: __('Statistics') }, { label: __('Agents') }]"
    :tabs="tabs"
    :active-tab="activeTab"
    width="full"
  >
    <div class="flex flex-col gap-6 p-4">
      <StatisticsPeriodFilter />

      <StatisticsPanel
        :title="$t('By agent')"
        :hint="
          $t('Workload is a snapshot of the present; the other figures cover the selected period.')
        "
        :has-data="agents.length > 0"
        :loading="loading"
      >
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-neutral-100 text-left dark:border-gray-900">
                <th class="py-2 pe-3 font-medium text-stone-200 dark:text-neutral-500">
                  {{ $t('Agent') }}
                </th>
                <th
                  v-for="column in columns"
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
                  v-for="column in columns"
                  :key="column.key"
                  class="py-2 pe-3 text-end text-gray-100 tabular-nums dark:text-neutral-400"
                >
                  {{ column.value(agent) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </StatisticsPanel>
    </div>
  </LayoutContent>
</template>
