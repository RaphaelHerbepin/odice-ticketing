# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — la page Version dit sur quelle instance on se trouve.
#
# « Ceci est la version 7.2.x-31768fce de Zammad » est rigoureusement identique
# sur les deux instances : c'est précisément la page qu'on ouvre pour savoir où
# l'on est, et elle ne le dit pas. On y ajoute donc l'environnement.
#
# Le contrôleur d'origine n'est pas exposé globalement — CoffeeScript compile
# chaque fichier dans sa propre portée — mais `App.Config` en garde la
# référence. On l'étend plutôt que de le réécrire : la page suit ainsi toute
# évolution amont, et seule la mention est à nous.
#
# `require_tree` charge dans l'ordre alphabétique : le préfixe « zzz_ »
# garantit que ce fichier passe APRÈS `version.coffee`. Fichier NOUVEAU, donc
# aucun fichier Zammad n'est modifié.

class OdiceVersion extends (App.Config.get('Version').controller)
  render: ->
    super

    environment = App.Config.get('odice_environment')
    return if !environment or environment is 'production'

    @$('.page-content').prepend(
      $('<p class="odice-version-environment"></p>').text(
        App.i18n.translateContent(
          'Staging instance — fictitious data, changes here have no effect on production.'
        )
      )
    )

App.Config.set(
  'Version',
  {
    prio: 3830
    name: __('Version')
    parent: '#system'
    target: '#system/version'
    controller: OdiceVersion
    permission: ['admin']
  },
  'NavBarAdmin'
)
