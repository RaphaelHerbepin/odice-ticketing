// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { i18n } from '#shared/i18n/index.ts'

import type { BarSeriesOption, LineSeriesOption } from 'echarts/charts'
import type {
  TitleComponentOption,
  TooltipComponentOption,
  LegendComponentOption,
  GridComponentOption,
} from 'echarts/components'
import type { ComposeOption } from 'echarts/core'

export type StatisticsChartOptions = ComposeOption<
  | TitleComponentOption
  | TooltipComponentOption
  | LegendComponentOption
  | BarSeriesOption
  | LineSeriesOption
  | GridComponentOption
>

export interface ChartBucket {
  label: string
  count: number
}

export interface TimePoint {
  date: string
  created: number
  closed: number
  timeLoggedMinutes: number
}

/* Couleurs de marque. Elles sont posées dans l'option plutôt que dans le
   composant : `useChartTheme` ne les applique pas, la bibliothèque laisse le
   style à l'appelant. */
export const brandColor = '#134c82'
export const accentColor = '#27a9ce'
export const warmColor = '#e08d3c'

/** Barres horizontales : elles restent lisibles avec des libellés longs
 *  (« Service Après-Vente ») là où un camembert devient illisible dès six
 *  catégories — et les axes en comptent jusqu'à quinze. */
export const barOption = (
  buckets: ChartBucket[] = [],
  color = brandColor,
): StatisticsChartOptions => ({
  tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
  grid: { left: 8, right: 16, top: 16, bottom: 8, containLabel: true },
  xAxis: { type: 'value', minInterval: 1 },
  yAxis: {
    type: 'category',
    // ECharts empile les catégories du bas vers le haut : on inverse pour que
    // la valeur la plus élevée apparaisse en haut.
    data: [...buckets].reverse().map((bucket) => bucket.label),
  },
  series: [
    {
      type: 'bar',
      data: [...buckets].reverse().map((bucket) => bucket.count),
      itemStyle: { color, borderRadius: [0, 4, 4, 0] },
      barMaxWidth: 22,
    },
  ],
})

/**
 * Libellé d'un point de la série, selon le pas.
 *
 * Le serveur renvoie toujours la date de début de période en ISO ; c'est ici
 * qu'elle devient lisible, parce que seul le client connaît la locale de
 * l'utilisateur. Une date affichée « 2026-09-22 » sur une page française n'est
 * pas fausse, elle est simplement illisible d'un coup d'œil.
 */
export const formatPointLabel = (iso: string, interval: string, locale?: string) => {
  const date = new Date(`${iso}T00:00:00`)

  if (interval === 'month') {
    return new Intl.DateTimeFormat(locale, { month: 'short', year: 'numeric' }).format(date)
  }
  if (interval === 'week') {
    // « sem. du 14/09 » : le numéro ISO de semaine ne parle à personne hors des
    // métiers qui s'en servent, la date de début situe immédiatement.
    const start = new Intl.DateTimeFormat(locale, { day: '2-digit', month: '2-digit' }).format(date)
    return `${i18n.t('week of')} ${start}`
  }
  return new Intl.DateTimeFormat(locale, { day: '2-digit', month: '2-digit' }).format(date)
}

/**
 * Créations, clôtures et temps saisi sur un même graphique.
 *
 * Le temps est une courbe sur un second axe, et non une troisième barre : il
 * ne se compte pas dans la même unité que des tickets, et les deux grandeurs
 * n'ont pas le même ordre de grandeur — une barre de 300 minutes écraserait
 * visuellement trois tickets créés jusqu'à les faire disparaître.
 */
export const timeSeriesOption = (
  points: TimePoint[] = [],
  interval = 'day',
  locale?: string,
): StatisticsChartOptions => {
  const hasTime = points.some((point) => point.timeLoggedMinutes > 0)

  return {
    tooltip: { trigger: 'axis' },
    legend: { top: 0 },
    grid: { left: 8, right: 16, top: 40, bottom: 8, containLabel: true },
    xAxis: {
      type: 'category',
      data: points.map((point) => formatPointLabel(point.date, interval, locale)),
    },
    yAxis: [
      { type: 'value', minInterval: 1, name: i18n.t('Tickets') },
      // Le second axe n'apparaît que si du temps a été saisi : un axe gradué en
      // minutes sur une série vide laisse croire à une mesure manquante.
      ...(hasTime
        ? [{ type: 'value' as const, name: i18n.t('Minutes'), splitLine: { show: false } }]
        : []),
    ],
    series: [
      {
        name: i18n.t('Created'),
        type: 'bar',
        data: points.map((point) => point.created),
        itemStyle: { color: brandColor, borderRadius: [3, 3, 0, 0] },
      },
      {
        name: i18n.t('Closed'),
        type: 'bar',
        data: points.map((point) => point.closed),
        itemStyle: { color: accentColor, borderRadius: [3, 3, 0, 0] },
      },
      ...(hasTime
        ? [
            {
              name: i18n.t('Time logged'),
              type: 'line' as const,
              yAxisIndex: 1,
              smooth: true,
              symbolSize: 6,
              data: points.map((point) => point.timeLoggedMinutes),
              itemStyle: { color: warmColor },
              lineStyle: { color: warmColor, width: 2 },
            },
          ]
        : []),
    ],
  }
}
