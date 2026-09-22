<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import { useStatisticsAxes } from '#desktop/pages/statistics/composables/useStatisticsAxes.ts'
import { useStatisticsExport } from '#desktop/pages/statistics/composables/useStatisticsExport.ts'
import { useStatisticsFilters } from '#desktop/pages/statistics/composables/useStatisticsFilters.ts'
import { useStatisticsPeriod } from '#desktop/pages/statistics/composables/useStatisticsPeriod.ts'

/* Les deux axes d'un croisement, quand la page en affiche un : l'onglet
   Croisement les transmet pour que le classeur porte le même tableau. */
const props = defineProps<{ rowAxis?: string; columnAxis?: string }>()

const { variables } = useStatisticsPeriod()
const { axes } = useStatisticsAxes()
const { restParams } = useStatisticsFilters(axes)
const { isExporting, exportStatistics } = useStatisticsExport()

/* Les paramètres de filtre viennent du MÊME composable que l'URL de la page :
   l'export ne peut donc pas porter sur autre chose que ce qui est affiché. */
const params = computed(() => {
  const search = new URLSearchParams(restParams.value)
  search.set('from', variables.value.from)
  search.set('to', variables.value.to)
  if (props.rowAxis && props.columnAxis) {
    search.set('row_axis', props.rowAxis)
    search.set('column_axis', props.columnAxis)
  }
  return search
})
</script>

<template>
  <!-- Avec libellé, et non à icône seule : « ce clic va me donner un fichier
       Excel » se lit, ne se devine pas. Le bouton n'est désactivé que pendant
       l'export lui-même — le griser en attendant les graphiques, dont il ne
       dépend pas, serait incompréhensible. -->
  <CommonButton
    :disabled="isExporting"
    prefix-icon="download"
    size="medium"
    variant="secondary"
    @click="exportStatistics(params)"
  >
    {{ $t('Export (.xlsx)') }}
  </CommonButton>
</template>
