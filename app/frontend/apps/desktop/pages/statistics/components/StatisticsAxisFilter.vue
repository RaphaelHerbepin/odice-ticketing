<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, ref } from 'vue'

import type {
  AxisDefinition,
  ActiveFilter,
} from '#desktop/pages/statistics/composables/useStatisticsFilters.ts'
import { UNSET } from '#desktop/pages/statistics/composables/useStatisticsFilters.ts'

const props = defineProps<{
  axes: AxisDefinition[]
  filters: ActiveFilter[]
  valuesFor: (axis: string) => string[]
}>()

const emit = defineEmits<{ change: [axis: string, values: string[]] }>()

/* Un sélecteur par axe ACTIF seulement, et un unique bouton pour en ajouter.
   Dix sélecteurs affichés d'emblée formeraient un mur repoussant les
   graphiques sous la ligne de flottaison, pour un réglage utilisé
   occasionnellement. */
const pendingAxis = ref<string | null>(null)

const activeNames = computed(() => new Set(props.filters.map((filter) => filter.axis)))

const openAxes = computed(() =>
  props.axes.filter((axis) => activeNames.value.has(axis.name) || axis.name === pendingAxis.value),
)

const addableAxes = computed(() =>
  props.axes
    .filter((axis) => !activeNames.value.has(axis.name) && axis.name !== pendingAxis.value)
    .map((axis) => ({ value: axis.name, label: axis.label })),
)

/* « Non renseigné » est proposé comme n'importe quelle autre réponse : c'est un
   seau visible sur les graphiques, et ne pas pouvoir cliquer dessus serait
   incompréhensible. La chaîne vide est la convention du serveur pour le dire. */
const optionsFor = (axis: AxisDefinition) => [
  ...axis.values.map((option) => ({ value: option.value, label: option.label })),
  { value: UNSET, label: __('Not set') },
]

const onSelect = (axis: string, values: unknown) => {
  emit('change', axis, (values as string[] | null) ?? [])
  if (pendingAxis.value === axis) pendingAxis.value = null
}
</script>

<template>
  <div class="flex flex-wrap items-end gap-3">
    <div v-for="axis in openAxes" :key="axis.name" class="min-w-56">
      <FormKit
        :id="`statistics-filter-${axis.name}`"
        type="select"
        :label="axis.label"
        :options="optionsFor(axis)"
        :value="valuesFor(axis.name)"
        :multiple="true"
        :clearable="true"
        :placeholder="$t('All')"
        no-options-label-translation
        @input="(values: unknown) => onSelect(axis.name, values)"
      />
    </div>

    <div v-if="addableAxes.length" class="min-w-56">
      <FormKit
        id="statistics-filter-add"
        type="select"
        :label="$t('Add a filter')"
        :options="addableAxes"
        :value="null"
        :multiple="false"
        :clearable="true"
        :placeholder="$t('Choose a field')"
        no-options-label-translation
        @input="(axis: unknown) => (pendingAxis = (axis as string | null) ?? null)"
      />
    </div>
  </div>
</template>
