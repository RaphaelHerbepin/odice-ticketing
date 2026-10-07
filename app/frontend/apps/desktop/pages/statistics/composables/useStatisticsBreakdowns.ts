// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { computed, type ComputedRef, type Ref } from 'vue'

import type { TicketStatisticsQuery } from '#shared/graphql/types.ts'

type Statistics = TicketStatisticsQuery['ticketStatistics']

export interface StatisticsBreakdown {
  key: string
  title: string
  buckets: { label: string; count: number }[]
  accent?: boolean
  /* Les libellés des axes métier sont définis par un administrateur et traduits
     par le SERVEUR : les repasser au catalogue du client chercherait une entrée
     qui ne peut pas exister. */
  translated?: boolean
}

/* Les répartitions de la vue d'ensemble.
 *
 * Extrait de la vue pour être vérifiable : le défaut qui a motivé ce fichier
 * était un libellé associé à la mauvaise source — « Par service » au-dessus du
 * décompte par GROUPE Zammad — et rien ne pouvait le détecter tant que
 * l'association vivait au milieu d'un template.
 */
export const useStatisticsBreakdowns = (
  statistics: Ref<Statistics | undefined>,
): ComputedRef<StatisticsBreakdown[]> => {
  /* Six répartitions, et non trois. Les trois premières décrivent la NATURE des
     demandes, les trois suivantes leur RÉPARTITION dans l'organisation — deux
     questions distinctes, que la page traitait à moitié. */
  const fixedBreakdowns = computed<StatisticsBreakdown[]>(() => [
    { key: 'state', title: __('By state'), buckets: statistics.value?.byState ?? [] },
    { key: 'priority', title: __('By priority'), buckets: statistics.value?.byPriority ?? [] },
    { key: 'channel', title: __('By channel'), buckets: statistics.value?.byChannel ?? [] },
    /* « Par groupe », et non « Par service » : ce panneau compte les tickets par
       GROUPE Zammad, c'est-à-dire la file qui les traite. Le mot « service »
       désigne ici tout autre chose — le service du demandeur, un attribut
       renseigné sur le ticket — et le panneau annonçait donc une statistique
       qu'il ne montrait pas : un décompte par file sous un titre promettant les
       services demandeurs. Ce service-là figure parmi les axes métier. */
    { key: 'group', title: __('By group'), buckets: statistics.value?.byGroup ?? [], accent: true },
    { key: 'owner', title: __('By agent'), buckets: statistics.value?.byOwner ?? [], accent: true },
    {
      key: 'organization',
      title: __('By organization'),
      buckets: statistics.value?.byOrganization ?? [],
      accent: true,
    },
  ])

  /* Les axes métier renseignés rejoignent la vue d'ensemble : ce sont les champs
     qui décrivent l'activité d'Odice — service du demandeur, agence, objet de la
     demande — et les reléguer à un onglet revenait à les tenir pour accessoires.
     Ceux qu'aucun ticket ne renseigne restent dans l'onglet dédié, où un cadre
     vide signifie « ce champ existe et personne ne le remplit » ; ici il
     allongerait la page sans rien dire. */
  const businessBreakdowns = computed<StatisticsBreakdown[]>(() =>
    [...(statistics.value?.byAxis ?? [])]
      .filter((axis) => axis.buckets.length > 0)
      .sort((a, b) => b.buckets.length - a.buckets.length)
      .map((axis) => ({
        /* Préfixé : rien n'interdit à un attribut personnalisé de s'appeler
           « state » ou « group », et deux clés identiques feraient disparaître
           un panneau au gré du rendu. */
        key: `axis:${axis.name}`,
        title: axis.label,
        translated: true,
        buckets: axis.buckets,
        accent: true,
      })),
  )

  return computed(() => [...fixedBreakdowns.value, ...businessBreakdowns.value])
}
