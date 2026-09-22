<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
defineProps<{
  title: string
  /** `false` affiche le message d'absence de données à la place du contenu. */
  hasData?: boolean
  loading?: boolean
  /** Précision affichée sous le titre, pour une lecture qui ne va pas de soi. */
  hint?: string
}>()
</script>

<template>
  <section
    class="rounded-lg border border-neutral-100 bg-neutral-50 p-4 dark:border-gray-900 dark:bg-gray-500"
  >
    <h2 class="text-base font-semibold text-gray-100 dark:text-neutral-400">{{ title }}</h2>
    <p v-if="hint" class="mt-1 text-xs text-stone-200 dark:text-neutral-500">{{ hint }}</p>
    <div class="mt-3">
      <slot v-if="!loading && hasData" />
      <p v-else-if="!loading" class="text-sm text-stone-200 dark:text-neutral-500">
        {{ $t('No data for this period.') }}
      </p>
    </div>
  </section>
</template>
