<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, nextTick, ref, useTemplateRef, watch } from 'vue'

import { EnumTicketOverviewColumnFilterOperator } from '#shared/graphql/types.ts'
import { i18n } from '#shared/i18n/index.ts'
import getUuid from '#shared/utils/getUuid.ts'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import CommonPopover from '#desktop/components/CommonPopover/CommonPopover.vue'
import { usePopover } from '#desktop/components/CommonPopover/usePopover.ts'
import type { TableAttribute } from '#desktop/components/CommonTable/types.ts'

import {
  columnFilterOperatorNeedsValue,
  columnFilterOperators,
  type TicketOverviewColumnFilter,
} from '../../composables/useTicketOverviewColumnFilters.ts'

interface Props {
  attribute: TableAttribute
  filter?: TicketOverviewColumnFilter
}

const props = defineProps<Props>()

const emit = defineEmits<{
  apply: [filter: TicketOverviewColumnFilter]
  remove: [column: string]
}>()

const { popover, popoverTarget, isOpen, toggle, close } = usePopover()

const label = computed(() =>
  i18n.t(props.attribute.label, ...(props.attribute.labelPlaceholder || [])),
)

const operator = ref(EnumTicketOverviewColumnFilterOperator.Contains)
const value = ref('')

const needsValue = computed(() => columnFilterOperatorNeedsValue(operator.value))

const canApply = computed(() => !needsValue.value || value.value.trim().length > 0)

const valueInput = useTemplateRef('value-input')

// À chaque ouverture, repartir du filtre en place (ou de « contient » vide).
watch(isOpen, (open) => {
  if (!open) return

  operator.value = props.filter?.operator ?? EnumTicketOverviewColumnFilterOperator.Contains
  value.value = props.filter?.value ?? ''

  nextTick(() => valueInput.value?.focus())
})

const apply = () => {
  if (!canApply.value) return

  emit('apply', {
    column: props.attribute.name,
    label: props.attribute.label,
    operator: operator.value,
    value: needsValue.value ? value.value.trim() : undefined,
  })

  close()
}

const remove = () => {
  emit('remove', props.attribute.name)
  close()
}

const inputId = `column-filter-${getUuid()}`
</script>

<template>
  <button
    ref="popoverTarget"
    v-tooltip="filter ? $t('Change filter on %s', label) : $t('Filter by %s', label)"
    type="button"
    class="ms-1 inline-flex shrink-0 items-center rounded-xs p-0.5 focus-visible:outline-1 focus-visible:outline-offset-1 focus-visible:outline-blue-800"
    :class="
      filter
        ? 'text-blue-800'
        : 'text-stone-200 hover:text-black dark:text-neutral-500 dark:hover:text-white'
    "
    :aria-pressed="!!filter"
    @click.stop="toggle(true)"
    @keydown.enter.stop
    @keydown.space.stop
  >
    <CommonIcon name="filter" size="xs" decorative />
  </button>

  <CommonPopover ref="popover" :owner="popoverTarget" orientation="autoVertical" placement="start">
    <form class="flex w-72 flex-col gap-3 p-3" @submit.prevent="apply">
      <CommonLabel class="block! font-semibold text-black! dark:text-white!" size="small">
        {{ $t('Filter by %s', label) }}
      </CommonLabel>

      <fieldset class="flex flex-col gap-1">
        <legend class="sr-only">{{ $t('Condition') }}</legend>
        <label
          v-for="item in columnFilterOperators"
          :key="item.value"
          :for="`${inputId}-${item.value}`"
          class="flex cursor-pointer items-center gap-2 rounded-md px-1.5 py-1 text-sm text-gray-100 hover:bg-blue-600 dark:text-neutral-400 dark:hover:bg-blue-900"
          :class="{ 'bg-blue-600 text-black! dark:bg-blue-900 dark:text-white!': operator === item.value }"
        >
          <input
            :id="`${inputId}-${item.value}`"
            v-model="operator"
            type="radio"
            class="accent-blue-800"
            :name="`${inputId}-operator`"
            :value="item.value"
          />
          {{ $t(item.label) }}
        </label>
      </fieldset>

      <label v-if="needsValue" :for="inputId" class="flex flex-col gap-1">
        <span class="sr-only">{{ $t('Value') }}</span>
        <input
          :id="inputId"
          ref="value-input"
          v-model="value"
          type="text"
          maxlength="255"
          autocomplete="off"
          class="w-full rounded-lg bg-blue-200 px-2.5 py-2 text-sm text-black outline-1 outline-offset-1 outline-transparent focus:outline-blue-800 dark:bg-gray-700 dark:text-white"
          :placeholder="$t('Text to search for')"
        />
      </label>

      <div class="flex items-center justify-end gap-2">
        <CommonButton v-if="filter" variant="remove" @click="remove">
          {{ $t('Remove filter') }}
        </CommonButton>
        <CommonButton type="submit" variant="submit" :disabled="!canApply">
          {{ $t('Apply') }}
        </CommonButton>
      </div>
    </form>
  </CommonPopover>
</template>
