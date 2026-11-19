<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { i18n } from '#shared/i18n/index.ts'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'

import {
  columnFilterOperatorNeedsValue,
  columnFilterOperators,
  type TicketOverviewColumnFilter,
} from '../../composables/useTicketOverviewColumnFilters.ts'

interface Props {
  filters: TicketOverviewColumnFilter[]
  totalCount?: number
  loading?: boolean
}

defineProps<Props>()

defineEmits<{
  remove: [column: string]
  clear: []
}>()

const describe = (filter: TicketOverviewColumnFilter) => {
  const operator = columnFilterOperators.find((item) => item.value === filter.operator)
  const parts = [i18n.t(filter.label), i18n.t(operator?.label ?? '')]

  if (columnFilterOperatorNeedsValue(filter.operator)) parts.push(`« ${filter.value} »`)

  return parts.join(' ')
}
</script>

<template>
  <div
    class="flex flex-wrap items-center gap-2 pb-2"
    role="region"
    :aria-label="$t('Column filters')"
  >
    <CommonIcon name="filter" size="xs" class="text-blue-800" decorative />

    <span
      v-for="filter in filters"
      :key="filter.column"
      class="inline-flex max-w-full items-center gap-1 rounded-full bg-blue-200 py-0.5 ps-2.5 pe-1 text-xs text-black dark:bg-gray-700 dark:text-white"
    >
      <span class="truncate">{{ describe(filter) }}</span>
      <button
        v-tooltip="$t('Remove filter')"
        type="button"
        class="inline-flex shrink-0 items-center rounded-full p-0.5 hover:bg-blue-600 focus-visible:outline-1 focus-visible:outline-blue-800 dark:hover:bg-blue-900"
        @click="$emit('remove', filter.column)"
      >
        <CommonIcon name="x-lg" size="xs" decorative />
      </button>
    </span>

    <CommonButton variant="subtle" @click="$emit('clear')">
      {{ $t('Clear filters') }}
    </CommonButton>

    <CommonLabel
      v-if="!loading && totalCount !== undefined"
      class="ms-auto"
      size="small"
      role="status"
    >
      {{ $t('%s matching ticket(s)', totalCount) }}
    </CommonLabel>
  </div>
</template>
