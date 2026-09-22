// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { useLocaleStore } from '#shared/stores/locale.ts'

/** Mise en forme commune à tous les onglets, pour que les mêmes grandeurs
 *  s'écrivent partout de la même façon. */
export const useStatisticsFormat = () => {
  const locale = useLocaleStore()

  const formatNumber = (value?: number | null) =>
    value === null || value === undefined
      ? '—'
      : new Intl.NumberFormat(locale.localeData?.locale).format(value)

  /** Minutes vers une durée lisible. Au-delà de 48 h on bascule en jours :
   *  « 72,4 h » ne se compare à rien dans la tête du lecteur. */
  const formatDuration = (minutes?: number | null) => {
    if (minutes === null || minutes === undefined) return '—'
    if (minutes < 60) return `${Math.round(minutes)} min`
    const hours = minutes / 60
    if (hours < 48) return `${hours.toFixed(1)} h`
    return `${(hours / 24).toFixed(1)} j`
  }

  const formatPercent = (value?: number | null) =>
    value === null || value === undefined ? '—' : `${value.toFixed(1)} %`

  return { formatNumber, formatDuration, formatPercent }
}
