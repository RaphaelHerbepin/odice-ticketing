<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

export interface CrossColumn {
  value?: string | null
  label: string
  count: number
}

export interface CrossRow {
  value?: string | null
  label: string
  total: number
  cells: number[]
}

const props = defineProps<{
  columns: CrossColumn[]
  rows: CrossRow[]
  total: number
  rowAxisLabel: string
  columnAxisLabel: string
}>()

/* L'intensité se normalise sur la CELLULE la plus forte, pas sur le total :
   rapportée au total, une répartition équilibrée donnerait un tableau
   uniformément pâle où plus rien ne se distingue. L'échelle est annoncée sous
   le tableau — une échelle muette s'interprète de travers. */
const peak = computed(() => props.rows.reduce((max, row) => Math.max(max, ...row.cells), 0))

/* Fond calculé en style inline, et non par une classe Tailwind construite :
   `bg-blue-${n}` n'existe pas, le compilateur ne génère que les classes qu'il
   voit écrites en toutes lettres, et l'on obtiendrait des cellules
   transparentes sans la moindre erreur.

   L'opacité est plafonnée et le texte garde son contraste plein : c'est ce qui
   garantit la lisibilité sans calculer une luminance par cellule, calcul qui
   laisse toujours une ou deux cases au seuil illisibles. */
const background = (count: number) => {
  if (!count || peak.value === 0) return undefined
  const ratio = Math.min(count / peak.value, 1)
  return {
    backgroundColor: `color-mix(in oklab, var(--color-blue-800) ${Math.round(ratio * 35)}%, transparent)`,
  }
}
</script>

<template>
  <div class="overflow-x-auto">
    <table class="w-full border-collapse text-sm">
      <caption class="sr-only">
        {{
          $t('Ticket count by %s and %s', rowAxisLabel, columnAxisLabel)
        }}
      </caption>

      <thead>
        <tr>
          <!-- Collante : sans elle, les libellés de ligne disparaissent dès le
               premier défilement horizontal et le tableau devient une grille de
               nombres sans entrée. Le fond opaque est indispensable, sinon les
               nombres défilent par transparence sous le libellé. -->
          <th
            scope="col"
            class="sticky start-0 z-10 bg-neutral-50 p-2 text-start font-medium text-stone-200 dark:bg-gray-500 dark:text-neutral-500"
          >
            {{ rowAxisLabel }}
          </th>
          <th
            v-for="column in columns"
            :key="column.label"
            scope="col"
            class="max-w-24 p-2 text-start align-bottom font-medium text-stone-200 dark:text-neutral-500"
          >
            <span v-tooltip="column.label">{{ column.label }}</span>
          </th>
          <th scope="col" class="p-2 text-end font-semibold text-gray-100 dark:text-neutral-400">
            {{ $t('Total') }}
          </th>
        </tr>
      </thead>

      <tbody>
        <tr
          v-for="row in rows"
          :key="row.label"
          class="border-t border-neutral-100 dark:border-gray-900"
        >
          <th
            scope="row"
            class="sticky start-0 z-10 bg-neutral-50 p-2 text-start font-normal text-gray-100 dark:bg-gray-500 dark:text-neutral-400"
          >
            {{ row.label }}
          </th>
          <!-- Le nombre est écrit dans chaque cellule : la couleur ne fait que
               le redoubler. C'est ce qui rend le tableau lisible sans
               distinguer les nuances, et imprimable. -->
          <td
            v-for="(cell, index) in row.cells"
            :key="index"
            class="p-2 text-center tabular-nums"
            :class="
              cell ? 'text-gray-100 dark:text-neutral-400' : 'text-stone-200 dark:text-neutral-500'
            "
            :style="background(cell)"
          >
            {{ cell }}
          </td>
          <td class="p-2 text-end font-semibold text-gray-100 tabular-nums dark:text-neutral-400">
            {{ row.total }}
          </td>
        </tr>
      </tbody>

      <tfoot>
        <tr class="border-t border-neutral-200 dark:border-gray-800">
          <th
            scope="row"
            class="sticky start-0 z-10 bg-neutral-50 p-2 text-start font-semibold text-gray-100 dark:bg-gray-500 dark:text-neutral-400"
          >
            {{ $t('Total') }}
          </th>
          <td
            v-for="column in columns"
            :key="column.label"
            class="p-2 text-center font-semibold text-gray-100 tabular-nums dark:text-neutral-400"
          >
            {{ column.count }}
          </td>
          <td class="p-2 text-end font-semibold text-gray-100 tabular-nums dark:text-neutral-400">
            {{ total }}
          </td>
        </tr>
      </tfoot>
    </table>

    <p class="mt-2 text-xs text-stone-200 dark:text-neutral-500">
      {{ $t('Shading runs from 0 to %s tickets, the busiest cell.', peak) }}
    </p>
  </div>
</template>
