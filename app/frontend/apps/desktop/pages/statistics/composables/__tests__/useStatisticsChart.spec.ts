// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import {
  formatPointLabel,
  timeSeriesOption,
  type TimePoint,
} from '#desktop/pages/statistics/composables/useStatisticsChart.ts'

const point = (date: string, timeLoggedMinutes = 0): TimePoint => ({
  date,
  created: 1,
  closed: 0,
  timeLoggedMinutes,
})

describe('formatPointLabel', () => {
  it('shows day and month at the day step', () => {
    expect(formatPointLabel('2026-09-22', 'day', 'fr-FR')).toBe('22/09')
  })

  it('names the start of the week rather than its ISO number', () => {
    expect(formatPointLabel('2026-09-21', 'week', 'fr-FR')).toContain('21/09')
  })

  it('drops the day at the month step', () => {
    expect(formatPointLabel('2026-09-01', 'month', 'fr-FR')).not.toContain('01')
  })

  // Une date ISO lue sans heure est interprétée en UTC par `Date`, ce qui recule
  // d'un jour à l'ouest de Greenwich — et décalerait tout l'axe.
  it('keeps the date the server sent, whatever the local timezone', () => {
    expect(formatPointLabel('2026-01-01', 'day', 'fr-FR')).toBe('01/01')
  })
})

describe('timeSeriesOption', () => {
  it('leaves out the time series and its axis when nothing was logged', () => {
    const option = timeSeriesOption([point('2026-09-21'), point('2026-09-22')], 'day', 'fr-FR')

    expect(option.series).toHaveLength(2)
    expect(option.yAxis).toHaveLength(1)
  })

  it('adds the time curve on a second axis as soon as time is logged', () => {
    const option = timeSeriesOption([point('2026-09-21'), point('2026-09-22', 42)], 'day', 'fr-FR')

    expect(option.series).toHaveLength(3)
    expect(option.yAxis).toHaveLength(2)

    const [, , time] = option.series as { type: string; yAxisIndex?: number }[]
    expect(time.type).toBe('line')
    expect(time.yAxisIndex).toBe(1)
  })

  it('plots one point per period, including the empty ones', () => {
    const option = timeSeriesOption(
      [point('2026-09-20'), point('2026-09-21'), point('2026-09-22')],
      'day',
      'fr-FR',
    )

    const [created] = option.series as { data: number[] }[]
    expect(created.data).toHaveLength(3)
  })
})
