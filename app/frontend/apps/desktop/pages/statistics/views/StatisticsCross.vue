<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import LayoutContent from '#desktop/components/layout/LayoutContent.vue'
import StatisticsCrossTable from '#desktop/pages/statistics/components/StatisticsCrossTable.vue'
import StatisticsExportButton from '#desktop/pages/statistics/components/StatisticsExportButton.vue'
import StatisticsPanel from '#desktop/pages/statistics/components/StatisticsPanel.vue'
import StatisticsToolbar from '#desktop/pages/statistics/components/StatisticsToolbar.vue'
import { useStatisticsAxes } from '#desktop/pages/statistics/composables/useStatisticsAxes.ts'
import { useStatisticsCrossAxes } from '#desktop/pages/statistics/composables/useStatisticsCrossAxes.ts'
import { useStatisticsFilters } from '#desktop/pages/statistics/composables/useStatisticsFilters.ts'
import { useStatisticsPeriod } from '#desktop/pages/statistics/composables/useStatisticsPeriod.ts'
import { useStatisticsTabs } from '#desktop/pages/statistics/composables/useStatisticsTabs.ts'
import { useTicketStatisticsCrosstabQuery } from '#desktop/pages/statistics/graphql/queries/ticketStatisticsCrosstab.api.ts'

const { tabs, activeTab } = useStatisticsTabs()
const { variables } = useStatisticsPeriod()
const { axes } = useStatisticsAxes()
const { filterVariables } = useStatisticsFilters(axes)
const { rowAxis, columnAxis, options, setRowAxis, setColumnAxis, swap } =
  useStatisticsCrossAxes(axes)

/* Tant que le catalogue d'axes n'est pas chargé, les deux noms sont vides et
   la requête serait refusée par le serveur, qui les exige. */
const ready = computed(() => Boolean(rowAxis.value && columnAxis.value))

const queryVariables = computed(() => ({
  ...variables.value,
  ...filterVariables.value,
  rowAxis: rowAxis.value,
  columnAxis: columnAxis.value,
}))

const { result, loading } = useTicketStatisticsCrosstabQuery(queryVariables, () => ({
  enabled: ready.value,
}))

const crosstab = computed(() => result.value?.ticketStatisticsCrosstab)

/* `model-value` est réactif : un changement d'URL réinjecte l'axe dans le champ,
   qui le réémet aussitôt. Sans cette comparaison, l'aller-retour se rejouerait à
   chaque navigation — et l'interversion des axes se défaîrait toute seule. */
const onAxisChange = (side: 'rows' | 'cols', name: unknown) => {
  const next = String(name ?? '')
  if (!next) return

  if (side === 'rows') {
    if (next !== rowAxis.value) setRowAxis(next)
  } else if (next !== columnAxis.value) {
    setColumnAxis(next)
  }
}
</script>

<template>
  <LayoutContent
    :breadcrumb-items="[{ label: __('Statistics') }, { label: __('Cross-tabulation') }]"
    :tabs="tabs"
    :active-tab="activeTab"
    width="full"
  >
    <template #headerRight>
      <StatisticsExportButton :row-axis="rowAxis" :column-axis="columnAxis" />
    </template>

    <div class="flex flex-col gap-6 p-4">
      <StatisticsToolbar />

      <div class="flex flex-wrap items-end gap-3">
        <div class="min-w-56">
          <!-- `model-value` et non `value` : FormKit ne lit `value` qu'au
               montage, donc le champ n'aurait jamais reflété l'axe réellement
               retenu — ni celui venu de l'URL, ni celui issu d'une
               interversion. -->
          <FormKit
            id="statistics-cross-rows"
            type="select"
            :label="$t('Rows')"
            :options="options"
            :model-value="rowAxis"
            :clearable="false"
            :no-options-label-translation="true"
            @update:model-value="(name: unknown) => onAxisChange('rows', name)"
          />
        </div>

        <CommonButton
          v-tooltip="$t('Swap rows and columns')"
          :aria-label="$t('Swap rows and columns')"
          class="mb-1"
          icon="arrow-repeat"
          size="medium"
          variant="secondary"
          @click="swap"
        />

        <div class="min-w-56">
          <FormKit
            id="statistics-cross-columns"
            type="select"
            :label="$t('Columns')"
            :options="options"
            :model-value="columnAxis"
            :clearable="false"
            :no-options-label-translation="true"
            @update:model-value="(name: unknown) => onAxisChange('cols', name)"
          />
        </div>
      </div>

      <StatisticsPanel
        :title="
          crosstab
            ? `${crosstab.rowAxis.label} × ${crosstab.columnAxis.label}`
            : $t('Cross-tabulation')
        "
        :hint="$t('Number of tickets created over the selected period.')"
        :has-data="!!crosstab?.rows.length"
        :loading="loading"
      >
        <StatisticsCrossTable
          v-if="crosstab"
          :columns="crosstab.columns"
          :rows="crosstab.rows"
          :total="crosstab.total"
          :row-axis-label="crosstab.rowAxis.label"
          :column-axis-label="crosstab.columnAxis.label"
        />
      </StatisticsPanel>
    </div>
  </LayoutContent>
</template>
