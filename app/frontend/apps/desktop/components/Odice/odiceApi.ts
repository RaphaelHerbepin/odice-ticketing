// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// Odice — appels REST vers les points d'entrée ODICE (config/routes/odice.rb).
// La session du navigateur suffit ; seul le jeton CSRF est à joindre.

import { getCSRFToken } from '#shared/server/apollo/utils/csrfToken.ts'

const request = async <T>(method: 'GET' | 'PUT', path: string, body?: unknown): Promise<T> => {
  const headers: Record<string, string> = { Accept: 'application/json' }
  const token = getCSRFToken()
  if (token) headers['X-CSRF-Token'] = token
  if (body !== undefined) headers['Content-Type'] = 'application/json'

  const response = await fetch(`/api/v1/odice/${path}`, {
    method,
    headers,
    credentials: 'same-origin',
    body: body === undefined ? undefined : JSON.stringify(body),
  })

  const data = await response.json().catch(() => ({}))

  if (!response.ok) {
    const message = (data as { error_human?: string; error?: string }).error_human
      || (data as { error?: string }).error
      || response.statusText
    throw new Error(message)
  }

  return data as T
}

export const updateOdiceNote = (articleInternalId: number, body: string) =>
  request<{ id: number; body: string }>('PUT', `article_notes/${articleInternalId}`, { body })
