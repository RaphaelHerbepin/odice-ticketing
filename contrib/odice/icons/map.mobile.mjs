// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// Odice — correspondance « nom d'icône Zammad » -> « nom d'icône Lucide », mobile.
//
// Le jeu mobile partage 77 noms avec le desktop : la table desktop est donc
// reprise puis complétée par les écarts propres au mobile.
// Comme pour le desktop, les noms identiques chez Lucide sont implicites.

import DESKTOP from './map.desktop.mjs'

export default {
  ...DESKTOP,

  // ---- Actions ----
  add: 'plus',
  'add-square': 'square-plus',
  close: 'x',
  'close-small': 'x',
  'close-keyboard': 'keyboard-off',
  delete: 'trash-2',
  edit: 'pencil',
  update: 'refresh-cw',
  paste: 'clipboard-paste',
  'change-order': 'arrow-up-down',
  install: 'download',

  // ---- Navigation ----
  caret: 'chevron-down',
  'caret-down': 'chevron-down',
  'caret-left': 'chevron-left',
  'caret-right': 'chevron-right',
  'caret-up': 'chevron-up',
  'double-arrow-left': 'chevrons-left',
  more: 'ellipsis',
  'more-vertical': 'ellipsis-vertical',
  home: 'house',

  // ---- Cases et validation ----
  'check-box-no': 'square',
  'check-box-yes': 'square-check',
  'check-circle-yes': 'circle-check',
  'check-double': 'check-check',
  'check-double-circle': 'circle-check-big',

  // ---- Visibilité ----
  hide: 'eye-off',
  show: 'eye',

  // ---- Entités ----
  person: 'user',
  organization: 'building-2',
  'new-organization': 'building-2',
  'new-customer': 'user-plus',
  'inactive-organization': 'building',
  'inactive-user': 'user-x',

  // ---- Communication ----
  mail: 'mail',
  'mail-out': 'send',
  message: 'message-circle',
  'phone-in': 'phone-incoming',
  'phone-out': 'phone-outgoing',
  'reply-alt': 'reply-all',
  note: 'square-pen',
  signature: 'signature',

  // ---- Notifications ----
  'notification-subscribed': 'bell',
  'notification-unsubscribed': 'bell-off',

  // ---- Contenu ----
  attachment: 'paperclip',
  audio: 'file-music',
  photos: 'image',
  web: 'globe',
  library: 'library',
  'knowledge-base': 'book-open',
  'internal-article': 'lock',
  language: 'languages',
  'ordered-list': 'list-ordered',
  summarize: 'text-quote',
  macros: 'zap',
  task: 'square-check-big',
  template: 'layout-template',
  puzzle: 'puzzle',

  // ---- Appareils ----
  desktop: 'monitor',
  'desktop-edit': 'monitor-cog',
  'mobile-code': 'smartphone',
  'ios-share': 'share',

  // ---- Sécurité ----
  'security-key': 'key-round',
  signed: 'badge-check',
  'not-signed': 'badge-x',
  'encryption-error': 'shield-alert',

  // ---- États ----
  loading: 'loader-circle',
  warning: 'triangle-alert',
  'vacation-mode': 'palmtree',

  // ---- Icônes absentes du jeu amont mais référencées par les alias ----
  'avatar-indicator-mobile': 'smartphone',
  'avatar-indicator-idle': 'moon',

  // ---- Éditeur ----
  'text-style-bold': 'bold',
  'text-style-italic': 'italic',
  'text-style-underline': 'underline',
  'text-style-strikethrough': 'strikethrough',
  'text-style-color': 'palette',
  'text-style-h': 'heading',
  'text-style-h1': 'heading-1',
  'text-style-h2': 'heading-2',
  'text-style-h3': 'heading-3',
}
