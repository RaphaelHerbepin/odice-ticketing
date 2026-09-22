<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
defineProps<{
  title: string
  /** `false` affiche le message d'absence de données à la place du contenu. */
  hasData?: boolean
  loading?: boolean
  /** Précision affichée sous le titre, pour une lecture qui ne va pas de soi. */
  hint?: string
  /**
   * Message d'absence, quand « aucune donnée sur cette période » désignerait
   * une mauvaise cause. Un tableau par agent vide parce qu'aucun ticket n'a de
   * propriétaire n'a rien à voir avec la période choisie, et laisser croire le
   * contraire envoie chercher la réponse là où elle n'est pas.
   */
  emptyMessage?: string
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
        {{ emptyMessage ? $t(emptyMessage) : $t('No data for this period.') }}
      </p>
    </div>
  </section>
</template>
