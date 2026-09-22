// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { computeTrend } from '#desktop/pages/statistics/composables/useStatisticsTrend.ts'

describe('absence de comparaison possible', () => {
  it('shows nothing when the current value is missing', () => {
    expect(computeTrend(null, 10, { direction: 'neutral', unit: 'count' })).toBeNull()
  })

  it('shows nothing when the preceding value is missing', () => {
    expect(computeTrend(10, undefined, { direction: 'neutral', unit: 'count' })).toBeNull()
  })

  // Le cas le plus fréquent en pratique : douze mois d'analyse sur une instance
  // ouverte depuis six mois. « +100 % » serait arbitraire, « +∞ » absurde.
  it('says so plainly rather than inventing a percentage from zero', () => {
    const trend = computeTrend(12, 0, { direction: 'up-is-good', unit: 'count' })
    expect(trend?.label).toBe('none over the preceding period')
    expect(trend?.tone).toBe('good')
  })

  it('reports an unchanged value as such', () => {
    const trend = computeTrend(7, 7, { direction: 'down-is-good', unit: 'count' })
    expect(trend?.label).toBe('no change')
    expect(trend?.tone).toBe('neutral')
    expect(trend?.direction).toBe('flat')
  })
})

describe('unités', () => {
  // « +18 % » sur un taux déjà exprimé en pourcentage est indécidable.
  it('expresses a rate in points, never in percent of a percent', () => {
    expect(computeTrend(84.2, 80, { direction: 'up-is-good', unit: 'percent' })?.label).toBe(
      '+4.2 pts',
    )
  })

  it('expresses a delay in its own unit', () => {
    expect(computeTrend(120, 198, { direction: 'down-is-good', unit: 'duration' })?.label).toBe(
      '−1.3 h',
    )
  })

  it('uses minutes below the hour', () => {
    expect(computeTrend(45, 30, { direction: 'down-is-good', unit: 'duration' })?.label).toBe(
      '+15 min',
    )
  })

  // Avec un seul agent, 1 → 3 tickets s'afficherait « +200 % ».
  it('falls back to an absolute gap when the baseline is too small', () => {
    expect(computeTrend(3, 1, { direction: 'neutral', unit: 'count' })?.label).toBe('+2')
  })

  it('uses a percentage once the baseline is large enough', () => {
    expect(computeTrend(118, 100, { direction: 'neutral', unit: 'count' })?.label).toBe('+18 %')
  })
})

describe('sens de lecture', () => {
  it('reads a shorter delay as good', () => {
    expect(computeTrend(100, 200, { direction: 'down-is-good', unit: 'duration' })?.tone).toBe(
      'good',
    )
  })

  it('reads a longer delay as bad', () => {
    expect(computeTrend(200, 100, { direction: 'down-is-good', unit: 'duration' })?.tone).toBe(
      'bad',
    )
  })

  it('reads a rising in-time rate as good', () => {
    expect(computeTrend(90, 80, { direction: 'up-is-good', unit: 'percent' })?.tone).toBe('good')
  })

  // Recevoir plus de tickets n'est en soi ni bon ni mauvais : colorer cette
  // carte porterait un jugement que la donnée ne soutient pas.
  it('passes no judgement on a volume', () => {
    expect(computeTrend(150, 100, { direction: 'neutral', unit: 'count' })?.tone).toBe('neutral')
    expect(computeTrend(50, 100, { direction: 'neutral', unit: 'count' })?.tone).toBe('neutral')
  })

  it('always carries the sign in the visible text, not only in the colour', () => {
    const worse = computeTrend(200, 100, { direction: 'down-is-good', unit: 'duration' })
    expect(worse?.label.startsWith('+')).toBe(true)
    const better = computeTrend(100, 200, { direction: 'down-is-good', unit: 'duration' })
    expect(better?.label.startsWith('−')).toBe(true)
  })
})
