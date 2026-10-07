// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { ref } from 'vue'

import { useStatisticsBreakdowns } from '../useStatisticsBreakdowns.ts'

const bucket = (label: string, count: number) => ({ label, count })

const statistics = (overrides: Record<string, unknown> = {}) =>
  ref({
    byState: [bucket('Ouvert', 3)],
    byPriority: [bucket('Normale', 3)],
    byChannel: [bucket('Courriel', 3)],
    byGroup: [bucket('IT', 17)],
    byOwner: [bucket('Agent', 2)],
    byOrganization: [bucket('Odice', 5)],
    byAxis: [],
    ...overrides,
     
  } as any)

describe('useStatisticsBreakdowns', () => {
  it('nomme « Par groupe » le décompte par groupe Zammad, et non « Par service »', () => {
    const breakdowns = useStatisticsBreakdowns(statistics())
    const group = breakdowns.value.find((item) => item.key === 'group')

    // Le défaut d'origine : ce panneau s'intitulait « By service » alors que
    // « service » désigne, chez Odice, le service du demandeur — un attribut
    // du ticket, sans rapport avec la file de traitement qu'il affichait.
    expect(group?.title).toBe('By group')
    expect(group?.buckets).toEqual([bucket('IT', 17)])
  })

  it('expose le service du demandeur à partir des axes métier', () => {
    const breakdowns = useStatisticsBreakdowns(
      statistics({
        byAxis: [
          {
            name: 'service_demandeur',
            label: 'Service du demandeur',
            buckets: [bucket('Commerce', 9), bucket('IT', 8)],
          },
        ],
      }),
    )

    const service = breakdowns.value.find((item) => item.key === 'axis:service_demandeur')

    expect(service?.title).toBe('Service du demandeur')
    expect(service?.buckets).toEqual([bucket('Commerce', 9), bucket('IT', 8)])
    // Le libellé vient déjà traduit du serveur : le repasser au catalogue du
    // client chercherait une entrée qui ne peut pas exister.
    expect(service?.translated).toBe(true)
  })

  it('écarte les axes qu’aucun ticket ne renseigne', () => {
    const breakdowns = useStatisticsBreakdowns(
      statistics({
        byAxis: [
          { name: 'agence', label: 'Agence', buckets: [] },
          { name: 'objet', label: 'Objet', buckets: [bucket('Panne', 4)] },
        ],
      }),
    )

    expect(breakdowns.value.map((item) => item.key)).not.toContain('axis:agence')
    expect(breakdowns.value.map((item) => item.key)).toContain('axis:objet')
  })

  it('préfixe les clés des axes, qu’un champ homonyme ne puisse masquer un panneau', () => {
    const breakdowns = useStatisticsBreakdowns(
      statistics({
        byAxis: [{ name: 'group', label: 'Groupe métier', buckets: [bucket('A', 1)] }],
      }),
    )

    const keys = breakdowns.value.map((item) => item.key)
    expect(new Set(keys).size).toBe(keys.length)
  })

  it('suit une statistique qui arrive après le premier rendu', () => {
    const source = ref(undefined)
    const breakdowns = useStatisticsBreakdowns(source)

    // Les six répartitions fixes existent dès le départ, vides.
    expect(breakdowns.value).toHaveLength(6)
    expect(breakdowns.value.every((item) => item.buckets.length === 0)).toBe(true)

     
    source.value = statistics({
      byAxis: [{ name: 'agence', label: 'Agence', buckets: [bucket('Nord', 2)] }],
    }).value as any

    expect(breakdowns.value).toHaveLength(7)
    expect(breakdowns.value.at(-1)?.title).toBe('Agence')
  })
})
