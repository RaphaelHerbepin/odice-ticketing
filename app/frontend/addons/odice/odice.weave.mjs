// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// Odice — modifications structurelles du frontend Vue.
//
// Ce manifeste est découvert automatiquement par le plugin Vite `addonWeave`
// (glob `**/*.weave.mjs` sous app/frontend). Il réécrit le source du composant
// EN MÉMOIRE, avant compilation : aucun fichier Zammad n'est modifié sur disque.
//
// ATTENTION : un sélecteur qui ne correspond à rien fait ÉCHOUER LE BUILD.
// C'est volontaire (on préfère un échec bruyant à une personnalisation
// silencieusement perdue), mais cela veut dire qu'une montée de version Zammad
// touchant l'un de ces composants doit être vérifiée ici.

export const addonWeaveRules = [
  {
    // Le composant porte d'ailleurs un TODO amont : « Add custom branding ».
    target:
      'apps/desktop/components/layout/LayoutSidebar/LeftSidebar/LeftSidebarHeader.vue',
    template: [
      {
        match: { component: 'CommonIcon', attr: { name: 'name', value: 'logo' } },
        setAttribute: { name: 'name', value: 'odice-mark' },
      },
    ],
  },
]
