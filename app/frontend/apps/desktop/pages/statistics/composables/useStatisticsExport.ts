// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { ref } from 'vue'

import { NotificationTypes } from '#shared/components/CommonNotifications/types.ts'
import { useNotifications } from '#shared/components/CommonNotifications/useNotifications.ts'
import { useApplicationStore } from '#shared/stores/application.ts'

const NOTIFICATION_ID = 'statistics-export'
const FALLBACK_NAME = 'statistiques.xlsx'

/**
 * Téléchargement du classeur Excel.
 *
 * Par `fetch` plutôt qu'en cliquant un lien fabriqué : un lien n'émet ni fin ni
 * erreur. Si le serveur répond 500, le navigateur enregistre la page d'erreur
 * ou ouvre un onglet blanc, et l'interface reste impassible — sur un export de
 * plusieurs secondes, c'est le scénario où l'on clique cinq fois.
 */
export const useStatisticsExport = () => {
  const application = useApplicationStore()
  const { notify } = useNotifications()

  const isExporting = ref(false)

  /* Le serveur nomme le fichier d'après la période analysée ; on le lui laisse
     faire. Forcer l'attribut `download` écraserait son en-tête. */
  const nameFromResponse = (response: Response) => {
    const disposition = response.headers.get('Content-Disposition') ?? ''
    const match = disposition.match(/filename="?([^";]+)"?/)
    return match?.[1] ?? FALLBACK_NAME
  }

  const exportStatistics = async (params: URLSearchParams) => {
    if (isExporting.value) return

    isExporting.value = true
    // Même identifiant que le message final, avec `unique` : le second remplace
    // le premier au lieu d'empiler deux bandeaux.
    notify({
      id: NOTIFICATION_ID,
      type: NotificationTypes.Info,
      message: __('Preparing the export…'),
    })

    let url: string | undefined

    try {
      const response = await fetch(
        `${application.config.api_path}/ticket_statistics/download?${params.toString()}`,
        { credentials: 'same-origin' },
      )
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const blob = await response.blob()
      url = URL.createObjectURL(blob)

      const link = document.createElement('a')
      link.href = url
      link.download = nameFromResponse(response)
      link.click()
      link.remove()

      notify({
        id: NOTIFICATION_ID,
        type: NotificationTypes.Success,
        message: __('The export has been downloaded.'),
      })
    } catch {
      // Persistant : un message d'échec qui s'efface en trois secondes n'a pas
      // été lu, et l'utilisateur croira que rien ne s'est passé.
      notify({
        id: NOTIFICATION_ID,
        type: NotificationTypes.Error,
        message: __('The export failed. Please try again.'),
        persistent: true,
      })
    } finally {
      if (url) URL.revokeObjectURL(url)
      isExporting.value = false
    }
  }

  return { isExporting, exportStatistics }
}
