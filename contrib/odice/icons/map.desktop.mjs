// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// Odice — correspondance « nom d'icône Zammad » -> « nom d'icône Lucide », desktop.
//
// Les noms identiques de part et d'autre ne figurent PAS ici : le script les
// résout implicitement. Cette table ne contient que les écarts.
//
// Valeur = un nom Lucide, ou { icon, filled, mirrored } pour les variantes.

export default {
  // ---- Flèches et navigation ----
  'arrow-bar-left': 'panel-left-close',
  'arrow-bar-right': 'panel-left-open',
  'arrow-clockwise': 'rotate-cw',
  'arrow-counterclockwise': 'rotate-ccw',
  'arrow-down-short': 'arrow-down',
  'arrow-up-short': 'arrow-up',
  'arrow-repeat': 'refresh-cw',
  'arrow-sm': 'chevron-right',
  'arrows-collapse': 'chevrons-down-up',
  'arrows-expand': 'chevrons-up-down',
  'arrows-fullscreen': 'maximize',
  'three-dots-vertical': 'ellipsis-vertical',
  'three-dots': 'ellipsis',
  backspace2: 'delete',

  // ---- Validation, cases, états ----
  check2: 'check',
  'check-all': 'check-check',
  'check2-all': 'check-check',
  'check2-circle': 'circle-check',
  'check2-all-circle': 'circle-check-big',
  'check-circle-outline': 'circle-check',
  'check-circle-outline-dashed': 'circle-dashed',
  'check-circle-no': 'circle',
  'check-square': 'square-check',
  'check2-square': 'square-check',
  'check-square-fill': 'square-check',
  checklist: 'list-checks',
  'radio-yes': 'circle-dot',
  'radio-no': 'circle',
  'square-fill': { icon: 'square', filled: true },
  'dash-circle': 'circle-minus',
  'dash-square': 'square-minus',
  'plus-circle': 'circle-plus',
  'plus-square': 'square-plus',
  'plus-square-fill': 'square-plus',
  'x-lg': 'x',
  'x-circle': 'circle-x',
  'patch-check': 'badge-check',
  'patch-x': 'badge-x',

  // ---- Fichiers et stockage ----
  'file-richtext': 'file-type',
  'file-play': 'file-video',
  'file-email': 'mail',
  'file-calendar': 'calendar-days',
  files: 'copy',
  floppy: 'save',
  trash3: 'trash-2',
  'archive-fill': 'archive',
  clipboard2: 'clipboard',

  // ---- Recherche et affichage ----
  'search-detail': 'scan-search',
  'eye-slash': 'eye-off',

  // ---- Personnes et entités ----
  'user-add': 'user-plus',
  'user-settings': 'user-cog',
  'user-inactive': 'user-x',
  'user-idle-2': 'user-round-minus',
  'person-x': 'user-x',
  'people-fill': 'users',
  buildings: 'building-2',
  'buildings-slash': 'building',
  'crown-silver': 'crown',
  book: 'book-open',

  // ---- Communication ----
  envelope: 'mail',
  at: 'at-sign',
  sms: 'message-square-text',
  chat: 'message-circle',
  'chat-left-text': 'message-square-text',
  'chat-right-text': { icon: 'message-square-text', mirrored: true },
  telephone: 'phone',
  'telephone-inbound': 'phone-incoming',
  'telephone-outbound': 'phone-outgoing',
  'phone-pencil': 'phone-call',
  phone: 'smartphone',
  'no-notifications': 'bell-off',
  fax: 'printer',

  // ---- Temps ----
  'clock-history': 'history',
  stopwatch: 'timer',
  'calendar-event': 'calendar-days',
  'calendar-date-time': 'calendar-clock',
  vacation2: 'palmtree',

  // ---- Système et sécurité ----
  gear: 'settings',
  unlock: 'lock-open',
  'lock-fill': 'lock',
  'unlock-fill': 'lock-open',
  'shield-lock': 'shield-check',
  'box-arrow-in-right': 'log-in',
  'box-arrow-up-right': 'external-link',
  'box-arrow-in-up-right': 'external-link',
  translate: 'languages',
  speedometer2: 'gauge',
  'brightness-alt-high': 'sun-medium',

  // ---- Éditeur de texte ----
  'type-bold': 'bold',
  'type-italic': 'italic',
  'type-underline': 'underline',
  'type-strikethrough': 'strikethrough',
  'type-h': 'heading',
  'type-h1': 'heading-1',
  'type-h2': 'heading-2',
  'type-h3': 'heading-3',
  'text-indent-left': 'indent-decrease',
  'text-indent-right': 'indent-increase',
  'list-ul': 'list',
  'list-ol': 'list-ordered',
  'list-columns-reverse': 'columns-2',
  'link-45deg': 'link-2',
  'input-cursor-text': 'text-cursor-input',
  'code-slash': 'code-xml',
  'code-square': 'square-code',
  color: 'palette',
  highlighter2: 'highlighter',
  'eraser-fill': 'eraser',
  'insert-hr': 'separator-horizontal',
  'remove-formatting': 'remove-formatting',
  'text-modules': 'text-quote',
  snippet: 'scissors',
  'card-list': 'list',
  'collection-play': 'gallery-vertical-end',
  'all-tickets': 'layers',

  // ---- Tableaux de l'éditeur ----
  'insert-column-after': 'between-horizontal-end',
  'insert-column-before': 'between-horizontal-start',
  'insert-row-after': 'between-vertical-end',
  'insert-row-before': 'between-vertical-start',
  'merge-cells': 'table-cells-merge',
  'split-cells': 'table-cells-split',
  'delete-column': 'table-columns-split',
  'delete-row': 'table-rows-split',
  'delete-table': 'table',
  'toggle-header-cell': 'square-dashed',
  'toggle-header-column': 'columns-2',
  'toggle-header-row': 'rows-2',

  // ---- Média ----
  'camera-video': 'video',
  'camera-video-off': 'video-off',
  'play-circle': 'circle-play',

  // ---- Retours et états ----
  'info-circle': 'info',
  'question-circle': 'circle-question-mark',
  'exclamation-triangle': 'triangle-alert',
  'warning-triangle': 'triangle-alert',
  'hand-thumbs-up': 'thumbs-up',
  'hand-thumbs-down': 'thumbs-down',
  lightning: 'zap',
  magic: 'wand-sparkles',
  spinner: 'loader-circle',

  // ---- Assistance IA ----
  'ai-agent': 'bot',
  'ai-knowledge-base': 'book-open',
  'smart-assist': 'sparkles',
  'smart-assist-elaborate': 'wand-sparkles',
  'check-circle-no-ai': 'circle-slash',

  // ---- Base de connaissances ----
  'kb-archived': 'archive',
  'kb-draft': 'file-pen',
  'kb-internal': 'lock',
  'kb-published': 'globe',
  'kba-add': 'file-plus',

  // ---- Priorités ----
  'priority-high-micro-2': 'chevrons-up',
  'priority-normal-micro-2': 'minus',
  'priority-low-micro-2': 'chevrons-down',

  // ---- Icônes absentes du jeu amont, pourtant référencées par
  //      desktopIconsAliasesMap.ts (alias morts corrigés côté Odice) ----
  'close-small': 'x',
  'check-double-circle': 'circle-check-big',
  'avatar-indicator-desktop': 'monitor',

  // ---- Page de statistiques Odice ----
  statistics: 'chart-column',

  // ---- Thème et divers ----
  'moon-stars': 'moon-star',
  'pencil-fill': 'pencil',
  'pencil-square': 'square-pen',
  'pin-angle': 'pin',
  'star-fill': { icon: 'star', filled: true },
}
