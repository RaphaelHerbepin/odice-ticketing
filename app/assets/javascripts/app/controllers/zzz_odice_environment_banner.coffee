# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — bandeau permanent sur les instances qui ne sont pas la production.
#
# Les deux instances servent la MÊME image : rien ne les distingue à l'écran, et
# l'on finit par modifier un vrai ticket en croyant être sur la copie. Le
# bandeau lève cette ambiguïté d'un coup d'œil, à tout instant.
#
# Le réglage vient du serveur (`odice_environment`, exposé au frontend par
# `odice:provision`) plutôt que du nom de domaine : celui-ci peut changer, pas
# l'intention.
#
# Fichier NOUVEAU, chargé par `require_tree ./controllers` : aucun fichier
# Zammad n'est modifié.
class OdiceEnvironmentBanner extends App.Controller
  constructor: ->
    super
    @render()

  render: ->
    environment = App.Config.get('odice_environment')
    return if !environment || environment is 'production'

    $('#app, .app').addClass('odice-has-environment-banner')
    $('body').addClass("odice-env-#{environment}")

    return if $('.odice-environment-banner').length

    $('body').prepend(
      $('<div class="odice-environment-banner" role="status"></div>').text(
        App.i18n.translateContent('Staging — fictitious data, changes here have no effect on production.')
      )
    )

App.Config.set('odice_environment_banner', OdiceEnvironmentBanner, 'Widgets')
