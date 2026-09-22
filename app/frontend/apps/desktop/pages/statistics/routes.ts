// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import type { RouteRecordRaw } from 'vue-router'

/* Quatre routes plutôt qu'un onglet piloté par un état local : chaque onglet a
 * son URL, donc se transmet et se met en favori. Seule la première porte
 * `mainNavigation`, sans quoi la navigation principale afficherait trois
 * entrées « Statistiques ». */
const shared = () => ({
  requiresAuth: true,
  requiredPermission: ['ticket.agent'],
})

const route: RouteRecordRaw[] = [
  {
    path: '/statistics',
    name: 'StatisticsOverview',
    props: true,
    component: () => import('./views/StatisticsOverview.vue'),
    meta: {
      ...shared(),
      title: __('Statistics'),
      icon: 'statistics',
      order: 200,
      mainNavigation: true,
    },
  },
  {
    path: '/statistics/axes',
    name: 'StatisticsAxes',
    props: true,
    component: () => import('./views/StatisticsAxes.vue'),
    meta: { ...shared(), title: __('Business axes'), icon: 'statistics', order: 0 },
  },
  {
    path: '/statistics/cross',
    name: 'StatisticsCross',
    props: true,
    component: () => import('./views/StatisticsCross.vue'),
    meta: { ...shared(), title: __('Cross-tabulation'), icon: 'statistics', order: 0 },
  },
  {
    path: '/statistics/agents',
    name: 'StatisticsAgents',
    props: true,
    component: () => import('./views/StatisticsAgents.vue'),
    meta: { ...shared(), title: __('Agents'), icon: 'statistics', order: 0 },
  },
]

export default route
