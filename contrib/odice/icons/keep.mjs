// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// Odice — icônes volontairement NON migrées vers Lucide.
//
// Lucide a retiré les logos de marque de son jeu en 2023 : il n'existe aucun
// équivalent, et redessiner une marque déposée en trait serait de toute façon
// discutable. Ces pictogrammes servent à identifier une provenance ou un
// fournisseur : l'utilisateur doit reconnaître la marque.

export default new Set([
  // Canaux et réseaux — indicateurs de provenance d'un ticket
  'facebook',
  'twitter',
  'x',
  'linkedin',
  'whatsapp',
  'telegram',
  'sina-weibo',
  'weibo',

  // Connexion tierce — les guidelines des fournisseurs imposent le logo officiel
  'github',
  'gitlab',
  'google',
  'microsoft',
  'apple',

  // Protocoles d'authentification (identité visuelle normée)
  'saml',
  'openid-connect',
  'sso',

  // Intégration CMDB tierce, multicolore par nature
  'i-doit-logo-dark',
  'i-doit-logo-light',

  // Marque Zammad : l'attribution « Powered by Zammad » du pied de page public
  // relève de la licence AGPL. La marque Odice de la barre latérale passe par
  // une icône distincte (odice-mark), pas par un remplacement de celle-ci.
  'logo',
  'logo-flat',

  // Marque Odice : dessinée à partir du pictogramme de la charte, elle n'a pas
  // d'équivalent Lucide et ne doit jamais être écrasée par une migration.
  'odice-mark',
])
