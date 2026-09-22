// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'

/**
 * Période d'analyse et pas de la série temporelle, partagés par tous les
 * onglets.
 *
 * Les deux vivent dans la query string plutôt que dans un état local : passer
 * d'un onglet à l'autre conserve alors le réglage, et surtout une URL se
 * transmet telle quelle — « regarde /statistics/axes?days=90 » est le cas
 * d'usage normal d'un responsable qui veut montrer un chiffre à quelqu'un.
 */
export const periods = [
  { days: 7, label: __('7 days') },
  { days: 30, label: __('30 days') },
  { days: 90, label: __('90 days') },
  { days: 365, label: __('12 months') },
]

/**
 * Pas de la série. `auto` laisse le serveur choisir d'après l'étendue — c'est
 * le réglage par défaut, et le bon dans la quasi-totalité des cas : douze mois
 * au jour le jour produiraient 365 barres illisibles. Le choix explicite reste
 * ouvert pour comparer deux lectures d'une même période.
 */
export const intervals = [
  { key: 'auto', label: __('Automatic') },
  { key: 'day', label: __('By day') },
  { key: 'week', label: __('By week') },
  { key: 'month', label: __('By month') },
]

const DEFAULT_DAYS = 30

export const useStatisticsPeriod = () => {
  const route = useRoute()
  const router = useRouter()

  const selectedDays = computed<number>(() => {
    const raw = Number(route.query.days)
    return periods.some((period) => period.days === raw) ? raw : DEFAULT_DAYS
  })

  const selectedInterval = computed<string>(() => {
    const raw = String(route.query.step ?? '')
    return intervals.some((interval) => interval.key === raw) ? raw : 'auto'
  })

  const setDays = (days: number) => {
    router.replace({ query: { ...route.query, days: String(days) } })
  }

  const setInterval = (key: string) => {
    router.replace({ query: { ...route.query, step: key } })
  }

  /**
   * Bornes seules : ce que réclament les requêtes sans série temporelle.
   *
   * `to` est tronqué à la minute. Ce calcul est réévalué à chaque changement de
   * la query string ; à la milliseconde près, chaque navigation produirait des
   * bornes neuves, donc une clé de cache Apollo jamais réutilisée, une requête
   * réseau à chaque clic, et des totaux qui bougent de quelques unités entre
   * deux réglages sans que rien ne l'explique à l'écran.
   */
  const variables = computed(() => {
    const to = new Date()
    to.setSeconds(0, 0)
    const from = new Date(to.getTime() - selectedDays.value * 24 * 60 * 60 * 1000)
    return { from: from.toISOString(), to: to.toISOString() }
  })

  /**
   * Bornes et pas, pour les requêtes qui tracent une série.
   *
   * Jeu distinct, et non un seul enrichi : une variable qu'une opération ne
   * déclare pas voyage jusqu'au serveur pour y être ignorée en silence, et
   * l'ajouter partout obligerait chaque requête à déclarer un paramètre dont
   * elle n'a que faire.
   */
  const seriesVariables = computed(() => ({
    ...variables.value,
    // `auto` n'est pas une valeur du serveur : ne rien envoyer est précisément
    // ce qui lui fait choisir le pas lui-même.
    interval: selectedInterval.value === 'auto' ? undefined : selectedInterval.value,
  }))

  return {
    periods,
    intervals,
    selectedDays,
    selectedInterval,
    setDays,
    setInterval,
    variables,
    seriesVariables,
  }
}
