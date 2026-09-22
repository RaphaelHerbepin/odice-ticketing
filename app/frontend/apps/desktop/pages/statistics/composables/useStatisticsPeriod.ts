// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'

/**
 * Période d'analyse, partagée par tous les onglets.
 *
 * Elle vit dans la query string plutôt que dans un état local : passer d'un
 * onglet à l'autre conserve alors la période, et surtout une URL se transmet
 * telle quelle — « regarde /statistics/axes?days=90 » est le cas d'usage
 * normal d'un responsable qui veut montrer un chiffre à quelqu'un.
 */
export const periods = [
  { days: 7, label: __('7 days') },
  { days: 30, label: __('30 days') },
  { days: 90, label: __('90 days') },
  { days: 365, label: __('12 months') },
]

const DEFAULT_DAYS = 30

export const useStatisticsPeriod = () => {
  const route = useRoute()
  const router = useRouter()

  const selectedDays = computed<number>(() => {
    const raw = Number(route.query.days)
    return periods.some((period) => period.days === raw) ? raw : DEFAULT_DAYS
  })

  const setDays = (days: number) => {
    router.replace({ query: { ...route.query, days: String(days) } })
  }

  const variables = computed(() => {
    const to = new Date()
    const from = new Date(to.getTime() - selectedDays.value * 24 * 60 * 60 * 1000)
    return { from: from.toISOString(), to: to.toISOString() }
  })

  return { periods, selectedDays, setDays, variables }
}
