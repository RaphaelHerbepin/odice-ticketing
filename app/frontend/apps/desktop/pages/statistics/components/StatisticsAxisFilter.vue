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

/**
 * Remontée d'une sélection vers l'URL.
 *
 * La comparaison n'est pas une optimisation : `model-value` étant réactif, un
 * changement d'URL réinjecte la valeur dans le champ, qui la réémet aussitôt.
 * Sans cette garde, l'aller-retour se rejouerait à chaque navigation.
 */
const onChange = (axis: string, values: unknown) => {
  const next = Array.isArray(values) ? (values as string[]) : []
  const current = props.valuesFor(axis)

  if (next.length === current.length && next.every((value, index) => value === current[index])) {
    return
  }

  emit('change', axis, next)
  if (pendingAxis.value === axis) pendingAxis.value = null
}
</script>

<template>
  <div class="flex flex-wrap items-end gap-3">
    <!--
      `model-value` et NON `value` : FormKit ne lit `value` qu'une seule fois, au
      montage (`cloneAny(context.attrs.value)`), et son observateur est réservé à
      `model-value`. Avec `value`, le champ envoyait bien les clics au parent
      mais restait sourd à ce que le parent lui renvoyait — la sélection
      n'apparaissait jamais, et de l'extérieur « il ne se passait rien ».

      Pas de `placeholder` : ce champ ne le déclare pas, l'attribut finissait sur
      un `<output>` où il n'a aucun effet, et le champ paraissait vide.
    -->
    <div v-for="axis in openAxes" :key="axis.name" class="min-w-56">
      <FormKit
        :id="`statistics-filter-${axis.name}`"
        type="select"
        :label="axis.label"
        :options="optionsFor(axis)"
        :model-value="valuesFor(axis.name)"
        :multiple="true"
        :clearable="true"
        :no-options-label-translation="true"
        @update:model-value="(values: unknown) => onChange(axis.name, values)"
      />
    </div>

    <!-- Celui-ci porte un état local et transitoire — quel axe on est en train
         d'ouvrir — et non un état d'URL : d'où le `v-model` sur son propre ref,
         qui le remet à vide de lui-même une fois le filtre posé. -->
    <div v-if="addableAxes.length" class="min-w-56">
      <FormKit
        id="statistics-filter-add"
        v-model="pendingAxis"
        type="select"
        :label="$t('Add a filter')"
        :options="addableAxes"
        :multiple="false"
        :clearable="true"
        :no-options-label-translation="true"
      />
    </div>
  </div>
</template>
