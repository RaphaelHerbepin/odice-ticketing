# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — renvoie l'entrée « Reporting » de l'interface historique vers la page
# Statistiques du nouveau frontend.
#
# Le module de rapports natif de Zammad exige Elasticsearch de façon bloquante,
# n'offre aucun axe de regroupement — sa seule dimension est le temps — et son
# catalogue de métriques est codé en dur. La page Odice fait strictement plus :
# axes métier, statistiques par agent, délais, respect des objectifs.
#
# `App.Config.set` écrase par clé, et `require_tree` charge dans l'ordre
# alphabétique : le préfixe « zzz_ » garantit que ce fichier passe APRÈS
# `report.coffee`, dont il remplace l'entrée. Fichier NOUVEAU, donc aucun
# fichier Zammad n'est modifié.

# Le gabarit de navigation rend `item.target` tel quel dans un href : une URL
# absolue suffit, aucun contrôleur n'est nécessaire.
App.Config.set('Reporting', {
  prio: 8000
  parent: ''
  name: __('Statistics')
  target: '/desktop/statistics'
  icon: 'report'
  # L'ancienne entrée exigeait la permission `report`. La page Odice est
  # accessible à tout agent — c'est la même autorisation que sa requête
  # GraphQL — donc la restreindre ici n'aurait servi qu'à la cacher.
  permission: ['ticket.agent']
}, 'NavBarRight')

# Les profils de rapport ne pilotent que le module natif, désormais hors
# service : on retire l'entrée d'administration plutôt que de laisser un écran
# qui ne mène nulle part.
App.Config.set('ReportProfile', {
  prio: 8000
  name: __('Report Profiles')
  parent: '#manage'
  target: '#manage/report_profiles'
  permission: ['admin.odice_reporting_disabled']
}, 'NavBarAdmin')
