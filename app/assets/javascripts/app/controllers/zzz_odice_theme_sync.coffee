# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — accorde le thème de l'interface historique avec celui du nouveau
# frontend.
#
# Les deux stacks lisent pourtant la même préférence (`preferences.theme`), mais
# le layout applique un thème AVANT que la session soit chargée. Il lui faut
# donc une trace locale de la préférence : ce contrôleur l'entretient.
#
# Le préfixe « zzz_ » n'est pas décoratif : App.Plugin instancie les plugins
# dans l'ordre alphabétique de leurs clés (app_post/plugin.coffee). Ce
# contrôleur doit passer APRÈS `theme`, sans quoi l'événement qu'il déclenche
# n'aurait encore aucun auditeur.
#
# Fichier NOUVEAU, chargé par le `require_tree ./controllers` de app/index.coffee :
# aucun fichier Zammad n'est modifié.

class App.OdiceThemeSync extends App.Controller
  constructor: ->
    super

    @controllerBind('ui:theme:changed', @remember)
    @controllerBind('ui:theme:saved', @remember)

    # Au démarrage, la session est déjà chargée : les plugins sont réinstanciés
    # à chaque `auth:login` (app_post/plugin.coffee). C'est donc le bon moment
    # pour rattraper l'écart laissé par le layout.
    @apply()

  preference: ->
    App.Session.get('preferences')?.theme

  remember: =>
    theme = @preference() or 'light'

    # Navigation privée ou stockage refusé : sans mémoire locale, le prochain
    # chargement repart du défaut clair — cohérent, donc rien à rattraper.
    try
      window.localStorage.setItem('odice_theme', theme)
    catch e
      undefined

  apply: =>
    theme = @preference()
    return @remember() if !theme

    @remember()
    App.Event.trigger('ui:theme:set', theme: theme)

App.Config.set('zzz_odice_theme_sync', App.OdiceThemeSync, 'Plugins')
