// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { renderComponent } from '#tests/support/components/index.ts'

import StatisticsAxisFilter from '#desktop/pages/statistics/components/StatisticsAxisFilter.vue'
import type { ActiveFilter } from '#desktop/pages/statistics/composables/useStatisticsFilters.ts'

const axes = [
  {
    name: 'agence',
    label: 'Agence',
    values: [
      { value: 'AGENCE NORD', label: 'AGENCE NORD' },
      { value: 'AGENCE SUD', label: 'AGENCE SUD' },
    ],
  },
  {
    name: 'service_demandeur',
    label: 'Service du demandeur',
    values: [{ value: 'IT', label: 'IT' }],
  },
]

const activeAgence: ActiveFilter[] = [
  { axis: 'agence', label: 'Agence', values: [{ value: 'AGENCE NORD', label: 'AGENCE NORD' }] },
]

const render = (filters: ActiveFilter[] = [], values: Record<string, string[]> = {}) =>
  renderComponent(StatisticsAxisFilter, {
    props: { axes, filters, valuesFor: (axis: string) => values[axis] ?? [] },
    form: true,
    router: true,
  })

describe('sélecteur des axes à filtrer', () => {
  it('offers every axis that is not already filtered', async () => {
    const view = render()

    expect(view.getByLabelText('Add a filter')).toBeInTheDocument()
    // Aucun axe n'est actif : aucun sélecteur de valeurs ne doit être monté.
    expect(view.queryByLabelText('Agence')).not.toBeInTheDocument()
  })

  it('leaves out an axis that is already filtered', () => {
    const view = render(activeAgence, { agence: ['AGENCE NORD'] })

    expect(view.getByLabelText('Agence')).toBeInTheDocument()
  })
})

describe('sélecteur de valeurs', () => {
  it('shows the value carried by the URL', () => {
    const view = render(activeAgence, { agence: ['AGENCE NORD'] })

    expect(view.getByText('AGENCE NORD')).toBeInTheDocument()
  })

  /* LE test qui manquait, et il doit porter sur un changement APRÈS le montage.
     FormKit lit `value` une seule fois, au montage : un test qui fournit la
     valeur dès le départ passe avec les deux câblages et ne prouve rien. Seule
     une mise à jour ultérieure distingue `value` de `model-value` — et c'est
     exactement ce que fait l'application quand l'URL change. */
  it('follows a value that changes after mount, which `value` alone would not', async () => {
    const view = render(activeAgence, { agence: ['AGENCE NORD'] })
    expect(view.queryByText('AGENCE SUD')).not.toBeInTheDocument()

    await view.rerender({
      filters: [
        {
          axis: 'agence',
          label: 'Agence',
          values: [
            { value: 'AGENCE NORD', label: 'AGENCE NORD' },
            { value: 'AGENCE SUD', label: 'AGENCE SUD' },
          ],
        },
      ],
      valuesFor: (axis: string) => (axis === 'agence' ? ['AGENCE NORD', 'AGENCE SUD'] : []),
    })

    expect(view.getByText('AGENCE SUD')).toBeInTheDocument()
  })

  it('reports a new selection to its parent', async () => {
    const view = render(activeAgence, { agence: ['AGENCE NORD'] })

    await view.events.click(view.getByLabelText('Agence'))
    await view.events.click(await view.findByRole('option', { name: 'AGENCE SUD' }))

    const emitted = view.emitted().change as unknown[][]
    expect(emitted).toBeTruthy()
    expect(emitted.at(-1)?.[0]).toBe('agence')
    expect(emitted.at(-1)?.[1]).toContain('AGENCE SUD')
  })

  // `model-value` étant réactif, le champ réémet ce qu'on lui réinjecte : sans
  // garde, l'aller-retour URL → champ → URL se rejouerait sans fin.
  it('stays silent when the value it receives has not changed', () => {
    const view = render(activeAgence, { agence: ['AGENCE NORD'] })

    expect(view.emitted().change).toBeUndefined()
  })
})
