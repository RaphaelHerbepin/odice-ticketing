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
# Le groupe est `Plugins`, et non `Widgets` : ce dernier n'est lu nulle part
# dans Zammad, une entrée qu'on y range n'est jamais instanciée. Ce sont les
# plugins que `App.Plugin.setupAll` construit au démarrage et à chaque
# `auth:login` / `auth:logout` (app_post/plugin.coffee), chacun dans un
# `try/catch` — une erreur ici ne peut donc pas empêcher l'application de
# démarrer.
#
# Fichier NOUVEAU, chargé par `require_tree ./controllers` : aucun fichier
# Zammad n'est modifié.
class App.OdiceEnvironmentBanner extends App.Controller
  constructor: ->
    super

    # Les réglages exposés au frontend peuvent arriver APRÈS l'instanciation
    # du plugin (chargement initial, puis rafraîchissement de la configuration).
    # Sans cette écoute, le bandeau manquerait au premier affichage et ne
    # reviendrait qu'au prochain login.
    @controllerBind('config_update_local', @render)

    @render()

  render: =>
    environment = App.Config.get('odice_environment')
    return if !environment or environment is 'production'

    $('#app, .app').addClass('odice-has-environment-banner')
    $('body').addClass("odice-env-#{environment}")

    # Le plugin est reconstruit à chaque login : sans cette garde, un bandeau
    # de plus s'empilerait à chaque fois.
    return if $('.odice-environment-banner').length

    $('body').prepend(
      $('<div class="odice-environment-banner" role="status"></div>').text(
        App.i18n.translatePlain('Staging — fictitious data, changes here have no effect on production.')
      )
    )

App.Config.set('zzz_odice_environment_banner', App.OdiceEnvironmentBanner, 'Plugins')
