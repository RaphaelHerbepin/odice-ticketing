<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import StatisticsAxisFilter from '#desktop/pages/statistics/components/StatisticsAxisFilter.vue'
import StatisticsFilterChips from '#desktop/pages/statistics/components/StatisticsFilterChips.vue'
import StatisticsPeriodFilter from '#desktop/pages/statistics/components/StatisticsPeriodFilter.vue'
import { useStatisticsAxes } from '#desktop/pages/statistics/composables/useStatisticsAxes.ts'
import { useStatisticsFilters } from '#desktop/pages/statistics/composables/useStatisticsFilters.ts'

/* Le pas de temps ne sert que là où une série temporelle est affichée :
   ailleurs, le proposer laisserait croire qu'il agit sur les chiffres. */
withDefaults(defineProps<{ showInterval?: boolean }>(), { showInterval: false })

const { axes } = useStatisticsAxes()
const { filters, filterCount, unknownAxes, valuesFor, setAxisValues, removeValue, clearFilters } =
  useStatisticsFilters(axes)

const missing = computed(() => unknownAxes.value.join(', '))
</script>

<template>
  <div class="flex flex-col gap-3">
    <StatisticsPeriodFilter :show-interval="showInterval" />

    <StatisticsAxisFilter
      :axes="axes"
      :filters="filters"
      :values-for="valuesFor"
      @change="setAxisValues"
    />

    <StatisticsFilterChips
      :filters="filters"
      :count="filterCount"
      @remove="removeValue"
      @clear="clearFilters"
    />

    <!-- Un filtre portant sur un champ supprimé depuis est retiré de la
         requête. Le taire ferait remonter tous les chiffres sans explication,
         sur une page qui affiche pourtant un filtre actif. -->
    <p v-if="unknownAxes.length" class="text-xs text-yellow-600 dark:text-yellow-400">
      {{
        $t(
          'This address filters on a field that no longer exists (%s); that filter is ignored.',
          missing,
        )
      }}
    </p>
  </div>
</template>
