<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<!--
  Odice — proposé juste après la clôture d'un ticket par l'agent : saisir la
  solution apportée (texte et/ou pièces jointes). Elle s'ajoute au fil comme une
  note, publique (visible du demandeur) ou interne, précédée de la mention
  « Ticket résolu et clôturé ». « Passer » ferme sans rien publier.
-->

<script setup lang="ts">
import { ref } from 'vue'

import { NotificationTypes } from '#shared/components/CommonNotifications/types.ts'
import { useNotifications } from '#shared/components/CommonNotifications/useNotifications.ts'
import { transformEditorHtml } from '#shared/components/Form/fields/FieldEditor/utils.ts'
import type { FileUploaded } from '#shared/components/Form/fields/FieldFile/types.ts'
import Form from '#shared/components/Form/Form.vue'
import type { FormSubmitData } from '#shared/components/Form/types.ts'
import { useForm } from '#shared/components/Form/useForm.ts'
import { useTicketUpdateMutation } from '#shared/entities/ticket/graphql/mutations/update.api.ts'
import { defineFormSchema } from '#shared/form/defineFormSchema.ts'
import { EnumUserErrorException, type TicketUpdateInput } from '#shared/graphql/types.ts'
import { MutationHandler } from '#shared/server/apollo/handler/index.ts'
import { convertFilesToAttachmentInput } from '#shared/utils/files.ts'

import CommonFlyout from '#desktop/components/CommonFlyout/CommonFlyout.vue'
import { closeFlyout } from '#desktop/components/CommonFlyout/useFlyout.ts'
import { provideFieldEditorOptions } from '#desktop/components/Form/fields/FieldEditor/useFieldEditorOptions.ts'

import { ODICE_SOLUTION_FLYOUT } from './odiceFlyouts.ts'

interface Props {
  ticketId: string
}

const props = defineProps<Props>()

interface SolutionFormData {
  public: boolean
  body?: string
  attachments?: FileUploaded[]
}

const FORM_ID = 'odice-solution'

const { form } = useForm()
const { notify } = useNotifications()

provideFieldEditorOptions({ zIndex: '40' })

const formSchema = defineFormSchema([
  {
    name: 'public',
    type: 'toggle',
    label: __('Visible to the customer'),
    value: false,
    props: {
      variants: { true: 'yes', false: 'no' },
    },
  },
  {
    name: 'body',
    label: __('Solution'),
    type: 'editor',
  },
  {
    name: 'attachments',
    label: __('Attachment'),
    labelSrOnly: true,
    type: 'file',
    props: { multiple: true },
  },
])

const mutation = new MutationHandler(useTicketUpdateMutation(), {
  errorNotificationMessage: __('The solution could not be added.'),
})

const saving = ref(false)

const hasText = (html: string) => html.replace(/<[^>]*>|&nbsp;/g, '').trim().length > 0

const save = async (data: FormSubmitData<SolutionFormData>) => {
  if (saving.value) return

  const body = data.body ? transformEditorHtml(data.body) : ''
  const attachments = convertFilesToAttachmentInput(FORM_ID, data.attachments)

  if (!hasText(body) && !attachments) {
    notify({
      id: 'odice-solution',
      message: __('Enter a solution or add an attachment, or skip.'),
      type: NotificationTypes.Warn,
    })
    return
  }

  saving.value = true

  const header = '<p><strong>✅ Ticket résolu et clôturé — Solution apportée :</strong></p>'

  const input: TicketUpdateInput = {
    article: {
      type: 'note',
      internal: !data.public,
      contentType: 'text/html',
      body: hasText(body) ? `${header}${body}` : header,
      attachments,
      preferences: { odice_solution: true },
    },
  }

  try {
    const result = await mutation.send({
      ticketId: props.ticketId,
      input,
      meta: {
        skipValidators: [
          EnumUserErrorException.ServiceTicketUpdateValidatorTimeAccountingError,
          EnumUserErrorException.ServiceTicketUpdateValidatorChecklistCompletedError,
        ],
      },
    })

    if (result?.ticketUpdate?.ticket) {
      notify({
        id: 'odice-solution',
        message: __('The solution has been added to the ticket.'),
        type: NotificationTypes.Success,
      })
      await closeFlyout(ODICE_SOLUTION_FLYOUT)
    }
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <CommonFlyout
    :name="ODICE_SOLUTION_FLYOUT"
    :header-title="__('Ticket closed – what was the solution?')"
    header-icon="check2-circle"
    :form="form"
    :footer-action-options="{
      actionLabel: __('Add the solution'),
      actionButton: { type: 'submit', disabled: saving },
      cancelLabel: __('Skip'),
    }"
    size="large"
    no-close-on-action
  >
    <Form
      :id="FORM_ID"
      ref="form"
      class="pt-4 pb-6"
      should-autofocus
      :schema="formSchema"
      @submit="save($event as FormSubmitData<SolutionFormData>)"
    />
  </CommonFlyout>
</template>
