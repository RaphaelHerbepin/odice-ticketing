<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import { useApplicationStore } from '#shared/stores/application.ts'

/**
 * Bandeau permanent sur les instances qui ne sont pas la production.
 *
 * Les deux instances servent la MÊME image : rien ne les distingue à l'écran,
 * et l'on finit par modifier un vrai ticket en croyant être sur la copie. Le
 * bandeau lève cette ambiguïté d'un coup d'œil.
 *
 * Le réglage vient du serveur plutôt que du nom de domaine : celui-ci peut
 * changer, pas l'intention. En production il vaut « production » et rien ne
 * s'affiche — la même image reste donc utilisable des deux côtés.
 *
 * Composant inséré dans les mises en page par `odice.weave.mjs`, sans modifier
 * de fichier Zammad.
 */
const application = useApplicationStore()

const environment = computed(() => application.config.odice_environment as string | undefined)

const visible = computed(() => Boolean(environment.value) && environment.value !== 'production')
</script>

<template>
  <!--
    `fixed` et `pointer-events-none` : le bandeau se superpose sans entrer dans
    le flux, donc sans décaler une grille de mise en page dont il n'est pas
    responsable, et sans jamais intercepter un clic.

    Ambre plutôt que rouge : c'est un avertissement permanent, pas une erreur —
    et le rouge s'use quand il reste affiché en continu.
  -->
  <div
    v-if="visible"
    role="status"
    class="pointer-events-none fixed inset-x-0 top-0 z-50 bg-amber-700 px-4 py-1 text-center text-xs font-semibold tracking-wide text-white"
  >
    {{ $t('Staging — fictitious data, changes here have no effect on production.') }}
  </div>
</template>
