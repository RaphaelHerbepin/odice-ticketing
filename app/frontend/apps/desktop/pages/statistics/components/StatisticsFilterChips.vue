<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import type { ActiveFilter } from '#desktop/pages/statistics/composables/useStatisticsFilters.ts'

defineProps<{ filters: ActiveFilter[]; count: number }>()

defineEmits<{
  remove: [axis: string, value: string]
  clear: []
}>()
</script>

<template>
  <!-- `aria-live` : sans annonce, l'effet d'un clic sur le reste de la page
       n'est jamais signalé à qui ne voit pas les graphiques se redessiner. -->
  <div
    v-if="filters.length"
    role="status"
    aria-live="polite"
    class="flex flex-wrap items-center gap-2"
  >
    <span class="sr-only">
      {{ $t('%s filter(s) active', count) }}
    </span>

    <template v-for="filter in filters" :key="filter.axis">
      <span
        v-for="value in filter.values"
        :key="`${filter.axis}-${value.value}`"
        class="inline-flex items-center gap-1 rounded-full bg-blue-100 py-1 ps-3 pe-1 text-sm text-gray-100 dark:bg-gray-500 dark:text-neutral-400"
      >
        <span class="text-stone-200 dark:text-neutral-500">{{ filter.label }} :</span>
        {{ value.label }}
        <CommonButton
          v-tooltip="$t('Remove the filter %s: %s', filter.label, value.label)"
          size="small"
          variant="neutral"
          icon="x-lg"
          :aria-label="$t('Remove the filter %s: %s', filter.label, value.label)"
          @click="$emit('remove', filter.axis, value.value)"
        />
      </span>
    </template>

    <button
      type="button"
      class="text-sm text-blue-800 underline underline-offset-2 hover:text-blue-600 dark:text-blue-500"
      @click="$emit('clear')"
    >
      {{ $t('Clear all filters') }}
    </button>
  </div>
</template>
