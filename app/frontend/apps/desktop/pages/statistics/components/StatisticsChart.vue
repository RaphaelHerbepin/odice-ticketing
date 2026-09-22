<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { BarChart, LineChart } from 'echarts/charts'
import {
  TitleComponent,
  TooltipComponent,
  LegendComponent,
  GridComponent,
  AriaComponent,
} from 'echarts/components'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import VChart from 'vue-echarts'

import { useChartTheme } from '#desktop/components/CommonCharts/useChartTheme.ts'
import type { StatisticsChartOptions } from '#desktop/pages/statistics/composables/useStatisticsChart.ts'

/* Copie délibérée de `CommonBarChart`, à une différence près : `LineChart` est
   enregistré en plus. ECharts n'affiche que les types de séries explicitement
   chargés, et le composant commun ne charge que les barres — une courbe y
   resterait invisible, sans erreur. Plutôt que de modifier un fichier Zammad
   pour un besoin qui n'est pas le sien, la page porte sa propre enveloppe : le
   thème, lui, reste celui du reste de l'interface. */
use([
  TitleComponent,
  TooltipComponent,
  LegendComponent,
  BarChart,
  LineChart,
  CanvasRenderer,
  GridComponent,
  AriaComponent,
])

defineProps<{ option: StatisticsChartOptions }>()

useChartTheme()
</script>

<template>
  <VChart :option="option" autoresize />
</template>
