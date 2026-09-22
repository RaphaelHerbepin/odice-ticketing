# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — normalisation et mise en forme des valeurs d'axe.
#
# Extrait de `Service::Ticket::Statistics` pour que le tableau croisé applique
# exactement les mêmes règles : deux écrans qui fusionnent différemment les
# valeurs non renseignées donnent deux chiffres différents pour la même
# question, et rien à l'écran n'explique l'écart.
module Service::Ticket::Statistics::Values
  module_function

  # Un champ jamais renseigné vaut NULL ; un champ vidé après coup vaut la
  # chaîne vide. La distinction est un accident du stockage, pas une
  # information : laissées telles quelles, elles produisaient deux seaux, dont
  # l'un sans étiquette du tout.
  #
  # `false` n'est pas concerné : un booléen à « non » est une réponse. D'où le
  # test sur `nil` et la chaîne vide, et non sur `blank?`.
  def merge_unset(counts)
    counts.each_with_object({}) do |(value, count), merged|
      merged[unset_key(value)] = (merged[unset_key(value)] || 0) + count
    end
  end

  def unset_key(value)
    value.is_a?(::String) && value.strip.empty? ? nil : value
  end

  def unset?(value)
    unset_key(value).nil?
  end

  # Les champs arborescents stockent le chemin complet avec « :: » pour
  # séparateur (« Flex::Bug ou erreur ») : illisible sur un graphique, le
  # chevron rend la hiérarchie sans l'expliquer.
  def humanize(value, locale)
    return ::Translation.translate(locale, 'Not set') if unset?(value)

    case value
    when true  then ::Translation.translate(locale, 'yes')
    when false then ::Translation.translate(locale, 'no')
    else value.to_s.gsub('::', ' › ')
    end
  end
end
