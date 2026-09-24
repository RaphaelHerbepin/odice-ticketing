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
# référence, SOUS LE GROUPE `NavBarAdmin` : `version.coffee` l'enregistre avec
# `App.Config.set('Version', …, 'NavBarAdmin')`, et `_configSingleton.set`
# range alors la valeur dans `@config['NavBarAdmin']['Version']`. La lire sans
# ce groupe renvoie `undefined`.
#
# Ce détail n'est pas cosmétique : tous les contrôleurs sont concaténés dans un
# seul `application.js`, donc une exception levée ICI, au niveau supérieur du
# fichier, interrompt l'exécution de TOUT le paquet. L'application reste alors
# sur son écran « Loading… », sur chaque page. D'où la garde ci-dessous : si
# l'entrée disparaissait un jour en amont, la page Version perdrait sa mention
# — et rien d'autre.
#
# `require_tree` charge dans l'ordre alphabétique : le préfixe « zzz_ »
# garantit que ce fichier passe APRÈS `version.coffee`. Fichier NOUVEAU, donc
# aucun fichier Zammad n'est modifié.

entree = App.Config.get('Version', 'NavBarAdmin')

if entree?.controller

  class OdiceVersion extends entree.controller
    render: ->
      super

      environment = App.Config.get('odice_environment')
      return if !environment or environment is 'production'

      @$('.page-content').prepend(
        $('<p class="odice-version-environment"></p>').text(
          App.i18n.translatePlain(
            'Staging instance — fictitious data, changes here have no effect on production.'
          )
        )
      )

  # L'entrée d'origine est reprise telle quelle et seul le contrôleur change :
  # une évolution amont de `prio`, de `permission` ou de la cible est ainsi
  # suivie sans que ce fichier ait à la connaître.
  App.Config.set('Version', $.extend({}, entree, controller: OdiceVersion), 'NavBarAdmin')
