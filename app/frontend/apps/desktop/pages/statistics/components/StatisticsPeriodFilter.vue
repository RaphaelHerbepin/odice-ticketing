<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { useStatisticsPeriod } from '#desktop/pages/statistics/composables/useStatisticsPeriod.ts'

/* Le pas n'est utile que là où une série temporelle est affichée : sur les
   pages qui n'en ont pas, le proposer laisserait croire qu'il agit sur les
   chiffres montrés. */
withDefaults(defineProps<{ showInterval?: boolean }>(), { showInterval: false })

const { periods, intervals, selectedDays, selectedInterval, setDays, setInterval } =
  useStatisticsPeriod()
</script>

<template>
  <div class="flex flex-wrap items-center gap-4">
    <div class="flex flex-wrap items-center gap-2">
      <span class="text-xs text-stone-200 dark:text-neutral-500">{{ $t('Period') }}</span>
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

    <div v-if="showInterval" class="flex flex-wrap items-center gap-2">
      <span class="text-xs text-stone-200 dark:text-neutral-500">{{ $t('Time step') }}</span>
      <button
        v-for="interval in intervals"
        :key="interval.key"
        type="button"
        class="rounded-md px-3 py-1.5 text-sm font-medium transition-colors"
        :class="
          selectedInterval === interval.key
            ? 'bg-blue-800 text-white'
            : 'bg-neutral-50 text-gray-100 hover:bg-blue-100 dark:bg-gray-500 dark:text-neutral-400'
        "
        @click="setInterval(interval.key)"
      >
        {{ $t(interval.label) }}
      </button>
    </div>
  </div>
</template>
