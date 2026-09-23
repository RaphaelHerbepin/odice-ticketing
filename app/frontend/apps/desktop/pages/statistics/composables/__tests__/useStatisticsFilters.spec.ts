// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { ref } from 'vue'

import {
  useStatisticsFilters,
  UNSET,
  type AxisDefinition,
} from '#desktop/pages/statistics/composables/useStatisticsFilters.ts'

const query = ref<Record<string, unknown>>({})
const replace = vi.fn((location: { query: Record<string, unknown> }) => {
  query.value = location.query
})

vi.mock('vue-router', () => ({
  useRoute: () => ({
    get query() {
      return query.value
    },
  }),
  useRouter: () => ({ replace }),
}))

const axes = ref<AxisDefinition[]>([
  {
    name: 'agence',
    label: 'Agence',
    values: [
      { value: 'AGENCE NORD', label: 'AGENCE NORD' },
      { value: 'AGENCE SUD', label: 'AGENCE SUD' },
    ],
  },
  {
    name: 'it_categorie',
    label: 'Objet de la demande',
    values: [{ value: 'Windows::Imprimante', label: 'Windows › Imprimante' }],
  },
])

beforeEach(() => {
  query.value = {}
  replace.mockClear()
})

describe('lecture de la query string', () => {
  // vue-router rend une chaîne, un tableau ou null selon la forme de l'URL.
  // Les trois arrivent en usage normal ; le dernier dès qu'on filtre sur
  // « non renseigné ».
  it('accepts a single value written as a plain string', () => {
    query.value = { 'f.agence': 'AGENCE NORD' }
    expect(useStatisticsFilters(axes).valuesFor('agence')).toEqual(['AGENCE NORD'])
  })

  it('accepts a repeated key as a list', () => {
    query.value = { 'f.agence': ['AGENCE NORD', 'AGENCE SUD'] }
    expect(useStatisticsFilters(axes).valuesFor('agence')).toEqual(['AGENCE NORD', 'AGENCE SUD'])
  })

  it('reads a valueless key as "not set"', () => {
    query.value = { 'f.agence': null }
    expect(useStatisticsFilters(axes).valuesFor('agence')).toEqual([UNSET])
  })

  it('ignores keys without the filter prefix', () => {
    query.value = { days: '90', step: 'week' }
    expect(useStatisticsFilters(axes).filters.value).toEqual([])
  })
})

describe('filtres actifs', () => {
  it('counts values and not axes', () => {
    query.value = {
      'f.agence': ['AGENCE NORD', 'AGENCE SUD'],
      'f.it_categorie': 'Windows::Imprimante',
    }
    expect(useStatisticsFilters(axes).filterCount.value).toBe(3)
  })

  it('labels a tree value with its chevron path', () => {
    query.value = { 'f.it_categorie': 'Windows::Imprimante' }
    const [filter] = useStatisticsFilters(axes).filters.value
    expect(filter.values[0].label).toBe('Windows › Imprimante')
  })

  // Une valeur retirée du champ depuis reste présente dans l'historique des
  // tickets : la masquer ferait disparaître un filtre pourtant actif.
  it('keeps a value the field no longer declares', () => {
    query.value = { 'f.agence': 'AGENCE FERMÉE' }
    const [filter] = useStatisticsFilters(axes).filters.value
    expect(filter.values[0].label).toBe('AGENCE FERMÉE')
  })

  it('reports axes the catalogue does not know, rather than dropping them silently', () => {
    query.value = { 'f.champ_supprime': 'x' }
    const { unknownAxes, filterVariables } = useStatisticsFilters(axes)
    expect(unknownAxes.value).toEqual(['champ_supprime'])
    expect(filterVariables.value.axisFilters).toEqual([])
  })

  it('orders filters by the axis catalogue, not by the URL', () => {
    query.value = { 'f.it_categorie': 'Windows::Imprimante', 'f.agence': 'AGENCE NORD' }
    expect(useStatisticsFilters(axes).filters.value.map((f) => f.axis)).toEqual([
      'agence',
      'it_categorie',
    ])
  })
})

describe('variables et paramètres', () => {
  it('sends the empty string for "not set", the server convention', () => {
    query.value = { 'f.agence': null }
    expect(useStatisticsFilters(axes).filterVariables.value).toEqual({
      axisFilters: [{ name: 'agence', values: [UNSET] }],
    })
  })

  // Les valeurs d'axe contiennent des espaces en pratique (« FROID CUISINE 33 »),
  // que l'encodage d'URL rend par des « + ». Le serveur les décode ; ce qui
  // compte est que l'aller-retour conserve la valeur exacte.
  it('builds REST parameters from the same source as the page URL', () => {
    query.value = { 'f.agence': ['AGENCE NORD', 'AGENCE SUD'] }
    const params = useStatisticsFilters(axes).restParams.value

    expect(params.toString()).toBe('f.agence=AGENCE+NORD&f.agence=AGENCE+SUD')
    expect(params.getAll('f.agence')).toEqual(['AGENCE NORD', 'AGENCE SUD'])
  })
})

describe('écriture', () => {
  it('drops the key entirely when the last value goes', () => {
    query.value = { days: '90', 'f.agence': 'AGENCE NORD' }
    useStatisticsFilters(axes).removeValue('agence', 'AGENCE NORD')
    expect(replace).toHaveBeenCalledWith({ query: { days: '90' } })
  })

  it('removes one value and keeps the others', () => {
    query.value = { 'f.agence': ['AGENCE NORD', 'AGENCE SUD'] }
    useStatisticsFilters(axes).removeValue('agence', 'AGENCE NORD')
    expect(replace).toHaveBeenCalledWith({ query: { 'f.agence': ['AGENCE SUD'] } })
  })

  // Vider les filtres ne doit pas emporter la période ni le pas de temps.
  it('clears filters without touching the other settings', () => {
    query.value = { days: '90', step: 'week', 'f.agence': 'AGENCE NORD', 'f.it_categorie': 'x' }
    useStatisticsFilters(axes).clearFilters()
    expect(replace).toHaveBeenCalledWith({ query: { days: '90', step: 'week' } })
  })
})
