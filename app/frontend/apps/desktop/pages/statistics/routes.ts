// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import type { RouteRecordRaw } from 'vue-router'

const route: RouteRecordRaw[] = [
  {
    path: '/statistics',
    name: 'Statistics',
    props: true,
    component: () => import('./views/Statistics.vue'),
    meta: {
      title: __('Statistics'),
      icon: 'statistics',
      requiresAuth: true,
      requiredPermission: ['ticket.agent'],
      order: 200,
      mainNavigation: true,
    },
  },
]

export default route
