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
  // Bandeau d'environnement, inséré comme FRÈRE de la racine et non en
  // l'enveloppant : envelopper changerait la grille de mise en page, dont ce
  // bandeau n'est pas responsable. Vue 3 accepte plusieurs racines, et le
  // composant se positionne en `fixed` — il ne décale donc rien.
  {
    target: 'apps/desktop/components/layout/LayoutPage.vue',
    scriptSetup:
      "import OdiceEnvironmentBanner from '#shared/components/Odice/OdiceEnvironmentBanner.vue'",
    template: [
      {
        match: { element: 'div', root: true },
        insertBefore: '<OdiceEnvironmentBanner />',
      },
    ],
  },
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
