<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import type { Trend } from '#desktop/pages/statistics/composables/useStatisticsTrend.ts'

const props = defineProps<{ trend: Trend | null; periodLabel: string }>()

/* La couleur n'arrive qu'après le signe et la flèche, et jamais seule : une
   flèche verte vers le bas sur « délai moyen » est juste, mais se lit à
   contresens par quiconque a intégré que le vert va vers le haut. C'est le
   « −1,3 h » écrit en toutes lettres qui lève l'ambiguïté. */
const toneClass = computed(() => {
  if (!props.trend || props.trend.tone === 'neutral') return 'text-stone-200 dark:text-neutral-500'
  return props.trend.tone === 'good'
    ? 'text-green-500 dark:text-green-400'
    : 'text-red-500 dark:text-red-400'
})

const arrow = computed(() => {
  if (!props.trend) return ''
  if (props.trend.direction === 'up') return '↑'
  if (props.trend.direction === 'down') return '↓'
  return '→'
})
</script>

<template>
  <!-- La ligne occupe sa place même vide : sans cela, la grille de cartes
       devient un escalier dès qu'une métrique n'a pas de comparaison. -->
  <div class="mt-1 min-h-4 text-xs" :class="toneClass">
    <template v-if="trend">
      <span aria-hidden="true">{{ arrow }}</span>
      {{ trend.label }}
      <span class="text-stone-200 dark:text-neutral-500">{{ periodLabel }}</span>
    </template>
  </div>
</template>
