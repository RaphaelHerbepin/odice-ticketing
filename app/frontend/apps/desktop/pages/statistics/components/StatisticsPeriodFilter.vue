<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { useStatisticsPeriod } from '#desktop/pages/statistics/composables/useStatisticsPeriod.ts'

const { periods, selectedDays, setDays } = useStatisticsPeriod()
</script>

<template>
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
      @click="setDays(period.days)"
    >
      {{ $t(period.label) }}
    </button>
  </div>
</template>
