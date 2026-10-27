<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<!-- Odice — modification d'une note interne déjà publiée (par son auteur). -->

<script setup lang="ts">
import { ref } from 'vue'

import { NotificationTypes } from '#shared/components/CommonNotifications/types.ts'
import { useNotifications } from '#shared/components/CommonNotifications/useNotifications.ts'
import { transformEditorHtml } from '#shared/components/Form/fields/FieldEditor/utils.ts'
import Form from '#shared/components/Form/Form.vue'
import type { FormSubmitData } from '#shared/components/Form/types.ts'
import { useForm } from '#shared/components/Form/useForm.ts'
import { defineFormSchema } from '#shared/form/defineFormSchema.ts'

import CommonFlyout from '#desktop/components/CommonFlyout/CommonFlyout.vue'
import { closeFlyout } from '#desktop/components/CommonFlyout/useFlyout.ts'
import { provideFieldEditorOptions } from '#desktop/components/Form/fields/FieldEditor/useFieldEditorOptions.ts'

import { updateOdiceNote } from './odiceApi.ts'
import { ODICE_NOTE_EDIT_FLYOUT } from './odiceFlyouts.ts'

interface Props {
  articleInternalId: number
  body: string
}

const props = defineProps<Props>()

const { form } = useForm()
const { notify } = useNotifications()

// Au-dessus du voile du panneau, comme TicketBulkEditFlyout.
provideFieldEditorOptions({ zIndex: '40' })

const formSchema = defineFormSchema([
  {
    name: 'body',
    label: __('Note'),
    labelSrOnly: true,
    type: 'editor',
    required: true,
  },
])

// Retire la mention « Modifiée le … » : le serveur la repose à jour.
const initialBody = props.body.replace(/<p>\s*<em>\s*✎ Modifiée le [^<]*<\/em>\s*<\/p>/g, '')

const saving = ref(false)

const save = async (data: FormSubmitData<{ body: string }>) => {
  if (saving.value) return
  saving.value = true

  try {
    await updateOdiceNote(props.articleInternalId, transformEditorHtml(data.body))
    notify({
      id: 'odice-note-edit',
      message: __('The note has been updated.'),
      type: NotificationTypes.Success,
    })
    await closeFlyout(ODICE_NOTE_EDIT_FLYOUT)
  } catch (error) {
    notify({
      id: 'odice-note-edit',
      message: (error as Error).message || __('The note could not be updated.'),
      type: NotificationTypes.Error,
    })
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <CommonFlyout
    :name="ODICE_NOTE_EDIT_FLYOUT"
    :header-title="__('Edit note')"
    header-icon="pencil"
    :form="form"
    :footer-action-options="{
      actionLabel: __('Save'),
      actionButton: { type: 'submit', disabled: saving },
    }"
    size="large"
    no-close-on-action
  >
    <!-- La vue ticket pose --top-header-height (hauteur de son en-tête) sur la page :
         sans remise à zéro, la barre d'outils collante de l'éditeur se place à cette
         distance dans le panneau et recouvre le texte. -->
    <div :style="{ '--top-header-height': '0px' }">
      <Form
        id="odice-note-edit"
        ref="form"
        class="pt-4 pb-6"
        should-autofocus
        :schema="formSchema"
        :initial-values="{ body: initialBody }"
        @submit="save($event as FormSubmitData<{ body: string }>)"
      />
    </div>
  </CommonFlyout>
</template>
