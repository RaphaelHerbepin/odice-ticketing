// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { renderComponent } from '#tests/support/components/index.ts'

import StatisticsCrossTable from '#desktop/pages/statistics/components/StatisticsCrossTable.vue'

const props = {
  rowAxisLabel: 'Agence',
  columnAxisLabel: 'Objet de la demande',
  columns: [
    { value: 'Matériel', label: 'Matériel', count: 5 },
    { value: null, label: 'Autres', count: 3 },
  ],
  rows: [
    { value: 'AGENCE NORD', label: 'AGENCE NORD', total: 6, cells: [4, 2] },
    { value: null, label: 'Autres', total: 2, cells: [1, 1] },
  ],
  total: 8,
}

describe('StatisticsCrossTable', () => {
  it('writes the count inside every cell, so the shading is only redundant', () => {
    const view = renderComponent(StatisticsCrossTable, { props })

    expect(view.getByRole('cell', { name: '4' })).toBeInTheDocument()
    // Un zéro doit s'écrire : une case vide ne se distingue pas d'une donnée
    // manquante, et n'est pas annoncée par un lecteur d'écran.
    const zeroProps = { ...props, rows: [{ ...props.rows[0], cells: [0, 6] }] }
    const withZero = renderComponent(StatisticsCrossTable, { props: zeroProps })
    expect(withZero.getByRole('cell', { name: '0' })).toBeInTheDocument()
  })

  it('names rows and columns with header cells, which is what makes the grid navigable', () => {
    const view = renderComponent(StatisticsCrossTable, { props })

    expect(view.getByRole('columnheader', { name: 'Matériel' })).toBeInTheDocument()
    expect(view.getByRole('rowheader', { name: 'AGENCE NORD' })).toBeInTheDocument()
  })

  it('shows the marginal totals, without which a grid of numbers has no entry point', () => {
    const view = renderComponent(StatisticsCrossTable, { props })

    expect(view.getByRole('cell', { name: '6' })).toBeInTheDocument()
    expect(view.getByRole('cell', { name: '8' })).toBeInTheDocument()
  })

  it('keeps the Others row and column, so the cells still add up to the total', () => {
    const view = renderComponent(StatisticsCrossTable, { props })

    expect(view.getAllByText('Autres')).toHaveLength(2)
  })

  it('describes the crossing for screen readers', () => {
    const view = renderComponent(StatisticsCrossTable, { props })

    expect(view.getByText('Ticket count by Agence and Objet de la demande')).toBeInTheDocument()
  })

  // Une échelle muette s'interprète de travers : l'intensité doit dire à quoi
  // elle se rapporte.
  it('states the scale the shading runs on', () => {
    const view = renderComponent(StatisticsCrossTable, { props })

    // La borne haute est la cellule la plus chargée, pas le total : rapportée
    // au total, une répartition équilibrée donnerait un tableau uniformément
    // pâle où plus rien ne se distingue.
    expect(
      view.getByText('Shading runs from 0 to 4 tickets, the busiest cell.'),
    ).toBeInTheDocument()
  })
})
