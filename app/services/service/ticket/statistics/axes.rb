# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — axes d'analyse disponibles pour les statistiques de tickets.
#
# Les champs qui structurent l'activité d'Odice (agence, service demandeur,
# objet de la demande…) sont des attributs personnalisés, donc des colonnes de
# `tickets` — ou de `users`, quand la question porte sur QUI demande plutôt que
# sur CE QUI est demandé. Les coder en dur ici obligerait à modifier ce fichier
# à chaque ajout de champ ; les laisser venir du client ouvrirait une injection
# SQL, puisqu'un nom de colonne ne peut pas être passé en paramètre lié.
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

  # Champs natifs du demandeur exposés comme axes, en plus de ses attributs
  # personnalisés. `department` est du texte libre : Zammad ne lui connaît pas
  # de liste d'options, mais c'est en pratique le service d'appartenance, saisi
  # dans un vocabulaire restreint. Ses valeurs sélectionnables sont donc
  # relevées en base (voir `observed_values`), faute de définition à lire.
  CUSTOMER_NATIVE = %w[department].freeze

  # Plafond des valeurs relevées pour un champ sans liste d'options. Au-delà, le
  # champ n'est pas un axe mais une zone de saisie, et une liste déroulante de
  # mille entrées ne rend service à personne.
  OBSERVED_VALUES_LIMIT = 100

  class UnknownAxis < StandardError; end

  # Un axe résolu : ce qu'il faut pour l'interroger sans jamais réinjecter le
  # nom reçu du client dans du SQL.
  #
  # `source` dit à quelle table appartient la colonne. C'est elle qui porte la
  # différence entre « ce qui est demandé » (`tickets`) et « qui le demande »
  # (`users`, par le demandeur du ticket).
  Definition = Struct.new(:name, :label, :source, :column, :values, keyword_init: true) do
    def model
      source == :customer ? ::User : ::Ticket
    end

    def node
      model.arel_table[column]
    end

    # `left_joins` et non `joins` : un INNER JOIN écarterait les tickets sans
    # demandeur, qui disparaîtraient des totaux sans que rien ne le signale.
    # Avec une jointure externe ils rejoignent le seau « Non renseigné », ce
    # qui est exactement ce qu'ils sont.
    #
    # ActiveRecord dédoublonne les jointures identiques : croiser deux axes du
    # demandeur, ou en filtrer un et grouper par l'autre, ne joint `users`
    # qu'une fois.
    def scoped(relation)
      source == :customer ? relation.left_joins(:customer) : relation
    end

    def string_column?
      model.columns_hash[column]&.type == :string
    end
  end

  class << self
    # Les axes proposables au client : nom logique, libellé, et les valeurs
    # sélectionnables. La colonne sous-jacente n'est jamais exposée.
    def available(locale = nil)
      definitions(locale).map { |axis| { name: axis.name, label: axis.label, values: axis.values } }
    end

    # Traduit un nom reçu du client en axe sûr.
    #
    # La double vérification n'est pas de la paranoïa : `ObjectManager::Attribute`
    # décrit ce qui DEVRAIT exister, `column_names` ce qui existe vraiment. Un
    # attribut ajouté mais dont la migration n'a pas encore tourné produirait
    # sinon un `GROUP BY` sur une colonne absente.
    def resolve(name)
      candidate = name.to_s
      found     = definitions.find { |axis| axis.name == candidate }
      raise UnknownAxis, "Axe d'analyse inconnu : #{candidate}" if found.nil?
      raise UnknownAxis, "Colonne absente pour l'axe : #{candidate}" if found.model.column_names.exclude?(found.column)

      found
    end

    def label(name, locale = nil)
      definitions(locale).find { |axis| axis.name == name.to_s }&.label || name.to_s
    end

    def valid?(name)
      resolve(name)
      true
    rescue UnknownAxis
      false
    end

    def names
      definitions.map(&:name)
    end

    # Les valeurs déclarées d'un axe, telles qu'un administrateur les a définies
    # — ou, pour un champ libre, celles qui sont effectivement employées.
    def values(name, locale = nil)
      definitions(locale).find { |axis| axis.name == name.to_s }&.values || []
    end

    private

    # Pas de mémoïsation de classe : elle survivrait à toute la vie du
    # processus, et un champ ajouté par un administrateur n'apparaîtrait
    # qu'après redémarrage des workers. La clé de cache porte la date de
    # dernière modification des attributs, donc s'invalide d'elle-même — et la
    # requête sous-jacente ne lit qu'une cinquantaine de lignes.
    #
    # Les valeurs RELEVÉES, elles, changent sans qu'aucun attribut ne bouge :
    # c'est l'expiration d'une heure qui les rafraîchit. Un service créé à
    # l'instant peut donc mettre jusqu'à une heure à devenir filtrable, alors
    # qu'il compte dès la première seconde dans les graphiques.
    def definitions(locale = nil)
      version = ::ObjectManager::Attribute.maximum(:updated_at).to_i
      # La locale entre dans la clé : les libellés sont traduits ici, et un
      # cache partagé entre locales servirait le français à un anglophone.
      key     = locale.presence || 'src'

      # Ce sont des HASHES qui sont mis en cache, pas les `Definition`
      # elles-mêmes : `Marshal` refuse de relire un Struct dont le nombre de
      # membres a changé, et le cache survivrait à un déploiement qui en ajoute
      # un. Les reconstruire à la lecture coûte le prix d'une boucle sur une
      # cinquantaine d'entrées.
      cached = ::Rails.cache.fetch("odice/statistics/axes/v2/#{version}/#{key}", expires_in: 1.hour) do
        load_definitions(locale).map(&:to_h)
      end

      cached.map { |attributes| Definition.new(**attributes) }
    end

    def load_definitions(locale = nil)
      ticket_definitions(locale) + customer_definitions(locale)
    end

    def ticket_definitions(locale)
      custom_attributes(::Ticket)
        .map do |attribute|
          Definition.new(
            name:   attribute.name,
            label:  translate(attribute.display, locale),
            source: :ticket,
            column: attribute.name,
            values: option_values(attribute, locale),
          )
        end
    end

    # Les axes portant sur le DEMANDEUR.
    #
    # Préfixés `customer.`, et non fondus dans la liste précédente : rien
    # n'interdit à un champ de ticket et à un champ d'utilisateur de porter le
    # même nom, et deux axes homonymes se seraient masqués l'un l'autre — le
    # filtre affichant les valeurs de l'un pour compter celles de l'autre.
    #
    # Le libellé le dit aussi à l'écran, sans quoi deux lignes « Service »
    # voisineraient dans la liste des filtres sans qu'on sache laquelle choisir.
    def customer_definitions(locale)
      attributes = custom_attributes(::User)
      natives    = CUSTOMER_NATIVE.select { |column| ::User.column_names.include?(column) }

      from_natives = natives.map do |column|
        Definition.new(
          name:   "customer.#{column}",
          label:  customer_label(column.humanize, locale),
          source: :customer,
          column: column,
          values: observed_values(column),
        )
      end

      from_attributes = attributes.map do |attribute|
        Definition.new(
          name:   "customer.#{attribute.name}",
          label:  customer_label(attribute.display, locale),
          source: :customer,
          column: attribute.name,
          values: option_values(attribute, locale),
        )
      end

      # Un champ natif que l'administration redéfinit ne doit pas apparaître
      # deux fois : la définition l'emporte, elle porte le libellé choisi.
      from_attributes + from_natives.reject { |native| from_attributes.any? { |defined| defined.name == native.name } }
    end

    def customer_label(display, locale)
      "#{translate('Requester', locale)} — #{translate(display, locale)}"
    end

    # Renvoie des objets ActiveRecord, consommés immédiatement : ce sont les
    # `Definition` qui sont mises en cache, pas eux.
    def custom_attributes(model)
      ::ObjectManager::Attribute
        .where(
          object_lookup_id: ::ObjectLookup.by_name(model.name),
          active:           true,
          data_type:        GROUPABLE_DATA_TYPES,
        )
        .reject { |attribute| EXCLUDED.include?(attribute.name) }
        .select { |attribute| model.column_names.include?(attribute.name) }
        .sort_by(&:display)
    end

    # Les valeurs SÉLECTIONNABLES viennent de la définition du champ, jamais des
    # seaux d'une agrégation : ceux-ci sont issus de la requête déjà filtrée,
    # donc cocher une agence ferait disparaître toutes les autres de la liste et
    # le filtre se refermerait sur lui-même. Ils sont aussi tronqués au top 15.
    #
    # Trois formats coexistent selon le type d'attribut, et le type arborescent
    # se lit en profondeur : ses valeurs stockées sont les chemins complets.
    def option_values(attribute, locale)
      options = attribute.data_option&.fetch('options', nil)
      return [] if options.blank?

      case options
      when ::Hash  then options.map { |value, label| { value: value.to_s, label: translate(label.to_s, locale) } }
      when ::Array then flatten_tree(options, locale)
      else []
      end
    end

    # Pour un champ libre, les valeurs employées tiennent lieu de définition.
    #
    # Relevées sur TOUS les utilisateurs, et non sur les tickets de la période
    # en cours : la liste des services ne doit pas se vider quand on restreint
    # la période, ni se refermer sur ce qu'on vient de cocher. Ce ne sont pas
    # des données de ticket mais des noms de services, dont la liste ne révèle
    # rien qu'un agent ne puisse voir.
    def observed_values(column)
      node = ::User.arel_table[column]

      ::User
        .where.not(column => [nil, ''])
        .distinct
        .order(node.asc)
        .limit(OBSERVED_VALUES_LIMIT)
        .pluck(column)
        .map { |value| { value: value.to_s, label: value.to_s } }
    rescue ::ActiveRecord::StatementInvalid
      # Une colonne absente ou d'un type inattendu ne doit pas faire disparaître
      # TOUS les axes : l'axe perd ses valeurs proposées, il reste comptable.
      []
    end

    def flatten_tree(nodes, locale, collected = [])
      Array(nodes).each do |node|
        value = node['value'] || node[:value]
        collected << { value: value.to_s, label: value.to_s.gsub('::', ' › ') } if value.present?
        flatten_tree(node['children'] || node[:children], locale, collected)
      end
      collected
    end

    def translate(text, locale)
      return text if locale.blank?

      ::Translation.translate(locale, text)
    end
  end
end
