// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import type { BarChartOptions } from '#desktop/components/CommonCharts/CommonBarChart/types.ts'

export interface ChartBucket {
  label: string
  count: number
}

/* Couleurs de marque. Elles sont posées dans l'option plutôt que dans le
   composant : `useChartTheme` ne les applique pas, la bibliothèque laisse le
   style à l'appelant. */
export const brandColor = '#134c82'
export const accentColor = '#27a9ce'

/** Barres horizontales : elles restent lisibles avec des libellés longs
 *  (« Service Après-Vente ») là où un camembert devient illisible dès six
 *  catégories — et les axes en comptent jusqu'à quinze. */
export const barOption = (buckets: ChartBucket[] = [], color = brandColor): BarChartOptions => ({
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
