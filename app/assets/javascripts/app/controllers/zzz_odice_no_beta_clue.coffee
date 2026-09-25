# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Odice — retrait de la bulle « New BETA UI » à la première connexion.
#
# Elle annonce aux agents qu'une nouvelle interface arrive « bientôt » et leur
# demande d'envoyer leur avis à Zammad. Le message s'adresse aux clients de la
# fondation, pas aux utilisateurs d'une instance déjà personnalisée : ici la
# nouvelle interface est en service, et l'avis ne remonterait à personne.
#
# Le DIDACTICIEL n'est pas touché. Les deux passent par des canaux distincts :
# le didacticiel est une route (`App.Config.set('clues', …, 'Routes')`, voir
# controllers/first_steps_clues.coffee), tandis que cette bulle est une entrée
# du groupe `Clues`, que dashboard.coffee parcourt APRÈS que le didacticiel a
# été achevé. Retirer l'entrée du groupe laisse donc le didacticiel intact —
# ainsi que la bulle des raccourcis clavier, qui partage ce groupe.
#
# Le bouton de bascule vers /desktop reste lui aussi en place : désactiver le
# réglage `ui_desktop_beta_switch` aurait suffi à masquer la bulle, mais aurait
# emporté le bouton et la redirection automatique.
#
# `require_tree` charge dans l'ordre alphabétique des entrées : le répertoire
# `clues/` passe avant ce fichier, dont le préfixe « zzz_ » garantit qu'il
# s'exécute une fois l'entrée posée. Fichier NOUVEAU : aucun fichier Zammad
# n'est modifié.
#
# Si une montée de version Zammad renommait cette clé, la suppression
# deviendrait sans effet — silencieusement. D'où la trace en console, qui ne
# coûte rien et se remarque le jour où la bulle réapparaît.
if App.Config.get('DesktopBetaSwitchClues', 'Clues')
  App.Config.delete('DesktopBetaSwitchClues', 'Clues')
else
  App.Log.notice 'odice', 'bulle « New BETA UI » introuvable : déjà retirée, ou renommée en amont.'
