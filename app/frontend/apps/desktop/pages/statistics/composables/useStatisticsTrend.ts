// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { i18n } from '#shared/i18n/index.ts'

/** Sens de lecture d'une évolution. Toutes les grandeurs n'en ont pas un. */
export type TrendDirection = 'up-is-good' | 'down-is-good' | 'neutral'

export type TrendUnit = 'count' | 'duration' | 'percent'

export interface Trend {
  /** Texte visible COMPLET : signe, quantité et unité. Déjà traduit. */
  label: string
  tone: 'good' | 'bad' | 'neutral'
  direction: 'up' | 'down' | 'flat'
}

export interface TrendOptions {
  direction: TrendDirection
  unit: TrendUnit
  /** En deçà de ce socle, l'écart s'exprime en absolu et non en pourcentage. */
  floor?: number
}

/**
 * Sous ce nombre de tickets sur la période précédente, un pourcentage ment par
 * omission : avec un seul agent, passer de 1 à 3 tickets affiche « +200 % » et
 * affole pour un écart qui n'est que du bruit.
 */
const RELATIVE_FLOOR = 10

const formatDuration = (minutes: number) => {
  const absolute = Math.abs(minutes)
  if (absolute < 60) return `${Math.round(absolute)} min`
  const hours = absolute / 60
  if (hours < 48) return `${hours.toFixed(1)} h`
  return `${(hours / 24).toFixed(1)} j`
}

const signed = (value: number, formatted: string) =>
  value >= 0 ? `+${formatted}` : `−${formatted}`

/**
 * Compare une valeur à celle de la période précédente.
 *
 * Renvoie `null` quand il n'y a rien d'honnête à afficher : une donnée
 * manquante d'un côté ou de l'autre ne devient pas « 0 % ».
 */
export const computeTrend = (
  current: number | null | undefined,
  previous: number | null | undefined,
  options: TrendOptions,
): Trend | null => {
  if (current === null || current === undefined) return null
  if (previous === null || previous === undefined) return null

  const delta = current - previous

  if (delta === 0) {
    return { label: i18n.t('no change'), tone: 'neutral', direction: 'flat' }
  }

  const direction = delta > 0 ? 'up' : 'down'
  const tone: Trend['tone'] =
    options.direction === 'neutral'
      ? 'neutral'
      : delta > 0 === (options.direction === 'up-is-good')
        ? 'good'
        : 'bad'

  /* Rien à quoi se comparer : « +100 % » serait arbitraire et « +∞ » absurde.
     Le cas est fréquent — douze mois d'analyse sur une instance ouverte depuis
     six mois donnent une fenêtre précédente entièrement vide, et toutes les
     cartes afficheraient la même valeur inventée. */
  if (previous === 0) {
    return { label: i18n.t('none over the preceding period'), tone, direction }
  }

  if (options.unit === 'percent') {
    // Un taux s'écarte en POINTS. « +18 % » sur un pourcentage est indécidable
    // — relatif ou absolu ? — et se lit de travers une fois sur deux.
    return {
      label: signed(delta, `${Math.abs(delta).toFixed(1)} ${i18n.t('pts')}`),
      tone,
      direction,
    }
  }

  if (options.unit === 'duration') {
    return { label: signed(delta, formatDuration(delta)), tone, direction }
  }

  const floor = options.floor ?? RELATIVE_FLOOR
  if (previous < floor) {
    return { label: signed(delta, String(Math.abs(delta))), tone, direction }
  }

  const percent = Math.round((delta / previous) * 100)
  return { label: signed(delta, `${Math.abs(percent)} %`), tone, direction }
}
