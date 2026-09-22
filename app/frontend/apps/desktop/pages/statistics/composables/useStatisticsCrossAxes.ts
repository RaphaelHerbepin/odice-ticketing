// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { computed, type Ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import type { AxisDefinition } from '#desktop/pages/statistics/composables/useStatisticsFilters.ts'

/**
 * Les deux axes du tableau croisé, portés par l'URL comme le reste des
 * réglages : « regarde /statistics/cross?rows=agence&cols=it_categorie » est
 * l'usage normal.
 */
export const useStatisticsCrossAxes = (axes: Ref<AxisDefinition[]>) => {
  const route = useRoute()
  const router = useRouter()

  const known = (name: unknown) =>
    typeof name === 'string' && axes.value.some((axis) => axis.name === name)

  /* À défaut de choix, les deux axes les plus fournis en valeurs — et non les
     deux premiers par ordre alphabétique, qui laisseraient souvent arriver sur
     un tableau vide. */
  const fallback = computed(() =>
    [...axes.value].sort((a, b) => b.values.length - a.values.length).map((axis) => axis.name),
  )

  const rowAxis = computed(() =>
    known(route.query.rows) ? String(route.query.rows) : (fallback.value[0] ?? ''),
  )

  const columnAxis = computed(() => {
    const requested = known(route.query.cols) ? String(route.query.cols) : undefined
    if (requested && requested !== rowAxis.value) return requested
    return fallback.value.find((name) => name !== rowAxis.value) ?? ''
  })

  const setAxes = (rows: string, cols: string) => {
    router.replace({ query: { ...route.query, rows, cols } })
  }

  /* Choisir en colonnes l'axe déjà en lignes PERMUTE les deux plutôt que
     d'afficher une erreur : c'est ce que l'utilisateur voulait dire neuf fois
     sur dix, et un message lui demanderait de faire lui-même l'échange. */
  const setRowAxis = (name: string) =>
    name === columnAxis.value ? setAxes(name, rowAxis.value) : setAxes(name, columnAxis.value)

  const setColumnAxis = (name: string) =>
    name === rowAxis.value ? setAxes(columnAxis.value, name) : setAxes(rowAxis.value, name)

  const swap = () => setAxes(columnAxis.value, rowAxis.value)

  const options = computed(() =>
    axes.value.map((axis) => ({ value: axis.name, label: axis.label })),
  )

  return { rowAxis, columnAxis, options, setRowAxis, setColumnAxis, swap }
}
