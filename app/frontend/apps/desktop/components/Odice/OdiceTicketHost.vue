<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<!--
  Odice — composant invisible monté dans la vue d'un ticket (/desktop) par le
  weave de TicketDetailViewContent.vue. Il déclare les panneaux ODICE de la vue :
  - « Modifier la note », ouvert par l'action d'article odiceNoteEdit ;
  - « Solution apportée », proposé quand l'agent courant vient de clôturer.
  Les vues de tickets restent montées en arrière-plan (onglets) : seule la vue
  active réagit.
-->

<script setup lang="ts">
import { onActivated, onBeforeUnmount, onDeactivated, onMounted, ref, watch } from 'vue'

import type { TicketById } from '#shared/entities/ticket/types.ts'
import {
  ODICE_NOTE_EDIT_EVENT,
  type OdiceNoteEditDetail,
} from '#shared/entities/ticket-article/action/plugins/odiceNoteEdit.ts'
import { useSessionStore } from '#shared/stores/session.ts'

import { useFlyout } from '#desktop/components/CommonFlyout/useFlyout.ts'

import { ODICE_NOTE_EDIT_FLYOUT, ODICE_SOLUTION_FLYOUT } from './odiceFlyouts.ts'

interface Props {
  ticket: TicketById
}

const props = defineProps<Props>()

const session = useSessionStore()

const noteEditFlyout = useFlyout({
  name: ODICE_NOTE_EDIT_FLYOUT,
  component: () => import('./OdiceNoteEditFlyout.vue'),
})

const solutionFlyout = useFlyout({
  name: ODICE_SOLUTION_FLYOUT,
  component: () => import('./OdiceSolutionFlyout.vue'),
  refocus: false,
})

const isActive = ref(true)
onActivated(() => {
  isActive.value = true
})
onDeactivated(() => {
  isActive.value = false
})

const onNoteEdit = (event: Event) => {
  const { detail } = event as CustomEvent<OdiceNoteEditDetail>
  if (!isActive.value || detail?.ticketId !== props.ticket.id) return

  noteEditFlyout.open({
    articleInternalId: detail.articleInternalId,
    body: detail.body,
  })
}

onMounted(() => window.addEventListener(ODICE_NOTE_EDIT_EVENT, onNoteEdit))
onBeforeUnmount(() => window.removeEventListener(ODICE_NOTE_EDIT_EVENT, onNoteEdit))

// Passage à un état de catégorie « closed », fait par l'agent courant.
watch(
  () => props.ticket.state?.stateType?.name,
  (newType, oldType) => {
    if (!oldType || oldType === 'closed' || newType !== 'closed') return
    if (!isActive.value) return
    if (props.ticket.updatedBy?.id !== session.userId) return

    solutionFlyout.open({ ticketId: props.ticket.id })
  },
)
</script>

<template>
  <span class="hidden" aria-hidden="true" />
</template>
