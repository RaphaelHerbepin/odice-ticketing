// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { computed, type Ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { i18n } from '#shared/i18n/index.ts'

export interface AxisDefinition {
  name: string
  label: string
  values: { value: string; label: string }[]
}

export interface ActiveFilter {
  axis: string
  label: string
  values: { value: string; label: string }[]
}

/**
 * Préfixe des paramètres de filtre dans l'URL.
 *
 * Les noms d'axes sont des champs personnalisés créés par un administrateur :
 * rien ne l'empêche d'en nommer un `days` ou `step`. Le préfixe isole leur
 * espace de noms de celui des réglages de la page.
 */
const PREFIX = 'f.'

/** Valeur portée dans l'URL pour « champ non renseigné ». */
export const UNSET = ''

/**
 * Normalise ce que `vue-router` renvoie pour une clé de query string.
 *
 * Il rend une chaîne quand la clé apparaît une fois, un tableau quand elle
 * apparaît plusieurs fois, et `null` pour `?f.agence` sans valeur. Les trois
 * cas arrivent en usage normal — dont le dernier, dès qu'on filtre sur « non
 * renseigné ». Sans cette normalisation, le composable rendrait tantôt une
 * chaîne tantôt un tableau à ses appelants.
 */
const toValues = (raw: unknown): string[] => {
  if (Array.isArray(raw)) return raw.map((value) => (value === null ? UNSET : String(value)))
  if (raw === null) return [UNSET]
  if (raw === undefined) return []
  return [String(raw)]
}

export const useStatisticsFilters = (axes: Ref<AxisDefinition[]>) => {
  const route = useRoute()
  const router = useRouter()

  const axisByName = computed(() => new Map(axes.value.map((axis) => [axis.name, axis])))

  /** Les valeurs retenues pour un axe, telles qu'elles figurent dans l'URL. */
  const valuesFor = (axis: string) => toValues(route.query[`${PREFIX}${axis}`])

  /* L'ordre suit celui du catalogue d'axes, et non celui de la query string :
     l'URL peut être écrite à la main, et les filtres sauteraient de place d'un
     chargement à l'autre. */
  const filters = computed<ActiveFilter[]>(() =>
    axes.value.flatMap((axis) => {
      const values = valuesFor(axis.name)
      if (values.length === 0) return []

      const byValue = new Map(axis.values.map((option) => [option.value, option.label]))

      return [
        {
          axis: axis.name,
          label: axis.label,
          values: values.map((value) => ({
            value,
            // Une valeur retirée du champ depuis reste présente dans
            // l'historique des tickets : on l'affiche telle quelle plutôt que
            // de la faire disparaître d'un filtre pourtant actif.
            label: value === UNSET ? i18n.t('Not set') : (byValue.get(value) ?? value),
          })),
        },
      ]
    }),
  )

  /* Le décompte porte sur les VALEURS et non sur les axes : annoncer « 2
     filtres » alors que six valeurs sont cochées serait faux. */
  const filterCount = computed(() =>
    filters.value.reduce((total, filter) => total + filter.values.length, 0),
  )

  /**
   * Axes nommés dans l'URL mais absents du catalogue — champ désactivé depuis,
   * lien enregistré il y a six mois. Le serveur les refuserait ; on les retire
   * des variables, mais on le signale : un filtre silencieusement ignoré gonfle
   * tous les chiffres de la page sans que rien ne l'explique.
   */
  const unknownAxes = computed(() =>
    Object.keys(route.query)
      .filter((key) => key.startsWith(PREFIX))
      .map((key) => key.slice(PREFIX.length))
      .filter((name) => !axisByName.value.has(name)),
  )

  const filterVariables = computed(() => ({
    axisFilters: filters.value.map((filter) => ({
      name: filter.axis,
      // La chaîne vide voyage jusqu'au serveur telle quelle : c'est déjà sa
      // convention pour « non renseigné », côté GraphQL comme côté REST.
      values: filter.values.map((value) => value.value),
    })),
  }))

  /** Mêmes filtres, en paramètres REST — pour que l'export ne puisse pas
   *  diverger de ce qui est à l'écran. */
  const restParams = computed(() => {
    const params = new URLSearchParams()
    filters.value.forEach((filter) => {
      filter.values.forEach((value) => params.append(`${PREFIX}${filter.axis}`, value.value))
    })
    return params
  })

  const replaceQuery = (mutate: (query: Record<string, unknown>) => void) => {
    const query = { ...route.query }
    mutate(query)
    router.replace({ query })
  }

  const setAxisValues = (axis: string, values: string[]) => {
    replaceQuery((query) => {
      if (values.length === 0) delete query[`${PREFIX}${axis}`]
      else query[`${PREFIX}${axis}`] = values
    })
  }

  const removeValue = (axis: string, value: string) => {
    setAxisValues(
      axis,
      valuesFor(axis).filter((current) => current !== value),
    )
  }

  const clearFilters = () => {
    replaceQuery((query) => {
      Object.keys(query)
        .filter((key) => key.startsWith(PREFIX))
        .forEach((key) => delete query[key])
    })
  }

  return {
    filters,
    filterCount,
    filterVariables,
    restParams,
    unknownAxes,
    valuesFor,
    setAxisValues,
    removeValue,
    clearFilters,
  }
}
