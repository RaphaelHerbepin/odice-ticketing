// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// Odice — « Modifier la note » sur ses propres notes internes, sans limite de
// temps. L'action ne fait que lever un événement : le panneau d'édition vit
// dans apps/desktop (OdiceTicketHost), que le code partagé ne doit pas importer.

import { useSessionStore } from '#shared/stores/session.ts'

import type { TicketArticleActionPlugin, TicketArticleAction } from './types.ts'

export const ODICE_NOTE_EDIT_EVENT = 'odice:note-edit'

export interface OdiceNoteEditDetail {
  ticketId: string
  articleId: string
  articleInternalId: number
  body: string
}

const actionPlugin: TicketArticleActionPlugin = {
  order: 998,

  addActions(ticket, article) {
    const session = useSessionStore()

    if (!article.internal) return []
    if (article.type?.name !== 'note') return []
    if (!article.author?.id || article.author.id !== session.userId) return []

    const action: TicketArticleAction = {
      apps: ['desktop'],
      label: __('Edit note'),
      name: 'odiceNoteEdit',
      icon: 'pencil',
      perform: () => {
        window.dispatchEvent(
          new CustomEvent<OdiceNoteEditDetail>(ODICE_NOTE_EDIT_EVENT, {
            detail: {
              ticketId: ticket.id,
              articleId: article.id,
              articleInternalId: article.internalId,
              body: article.bodyWithUrls,
            },
          }),
        )
      },
      view: {
        agent: ['change'],
      },
    }

    return [action]
  },
}

export default actionPlugin
