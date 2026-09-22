# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — axes d'analyse disponibles pour les statistiques de tickets.
#
# Les champs qui structurent l'activité d'Odice (agence, service demandeur,
# objet de la demande…) sont des attributs personnalisés, donc des colonnes de
# `tickets`. Les coder en dur ici obligerait à modifier ce fichier à chaque
# ajout de champ ; les laisser venir du client ouvrirait une injection SQL,
# puisqu'un nom de colonne ne peut pas être passé en paramètre lié.
#
# D'où cette liste blanche : elle est CONSTRUITE à partir de
# `ObjectManager::Attribute`, donc suit les champs réellement définis, et toute
# valeur reçue est résolue contre elle. Ce qui n'y figure pas est refusé.
class Service::Ticket::Statistics::Axes
  # Types d'attributs exploitables comme axe : des valeurs discrètes et en
  # nombre restreint. Un champ texte libre produirait autant de seaux que de
  # tickets, et une date autant que de jours — ni l'un ni l'autre n'est un axe.
  GROUPABLE_DATA_TYPES = %w[select tree_select boolean].freeze

  # Attributs techniques que Zammad expose comme `select` mais qui ont déjà
  # leur agrégation dédiée, avec résolution des libellés par jointure.
  EXCLUDED = %w[state_id priority_id group_id owner_id customer_id organization_id type].freeze

  class UnknownAxis < StandardError; end

  class << self
    # Les axes proposables au client : nom logique, libellé traduisible, et la
    # colonne sous-jacente — cette dernière n'est jamais exposée.
    def available
      attributes
    end

    # Traduit un nom reçu du client en nom de colonne sûr.
    #
    # La double vérification n'est pas de la paranoïa : `ObjectManager::Attribute`
    # décrit ce qui DEVRAIT exister, `Ticket.column_names` ce qui existe
    # vraiment. Un attribut ajouté mais dont la migration n'a pas encore tourné
    # produirait sinon un `GROUP BY` sur une colonne absente.
    def resolve(name)
      candidate = name.to_s
      raise UnknownAxis, "Axe d'analyse inconnu : #{candidate}" if names.exclude?(candidate)
      raise UnknownAxis, "Colonne absente pour l'axe : #{candidate}" if ::Ticket.column_names.exclude?(candidate)

      candidate
    end

    def label(name)
      attributes.find { |attribute| attribute[:name] == name.to_s }&.fetch(:label) || name.to_s
    end

    def valid?(name)
      resolve(name)
      true
    rescue UnknownAxis
      false
    end

    def names
      attributes.pluck(:name)
    end

    private

    # Pas de mémoïsation de classe : elle survivrait à toute la vie du
    # processus, et un champ ajouté par un administrateur n'apparaîtrait
    # qu'après redémarrage des workers. La clé de cache porte la date de
    # dernière modification des attributs, donc s'invalide d'elle-même — et la
    # requête sous-jacente ne lit qu'une cinquantaine de lignes.
    def attributes
      version = ::ObjectManager::Attribute.maximum(:updated_at).to_i

      ::Rails.cache.fetch("odice/statistics/axes/#{version}", expires_in: 1.hour) do
        load_attributes
      end
    end

    # Renvoie des hashes, pas des objets ActiveRecord : ce sont eux qui sont mis
    # en cache, et sérialiser un modèle complet serait à la fois lourd et
    # sensible à toute évolution du schéma.
    def load_attributes
      ::ObjectManager::Attribute
        .where(
          object_lookup_id: ::ObjectLookup.by_name('Ticket'),
          active:           true,
          data_type:        GROUPABLE_DATA_TYPES,
        )
        .reject { |attribute| EXCLUDED.include?(attribute.name) }
        .select { |attribute| ::Ticket.column_names.include?(attribute.name) }
        .sort_by(&:display)
        .map { |attribute| { name: attribute.name, label: attribute.display } }
    end
  end
end
