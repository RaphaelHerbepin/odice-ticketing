# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — restriction des statistiques à certaines valeurs d'un axe métier.
#
# Le nom d'axe vient du client, et il désigne une COLONNE : un nom de colonne ne
# peut pas être passé en paramètre lié, donc il doit impérativement être résolu
# contre la liste blanche d'`Axes` avant d'approcher la requête. C'est le seul
# rempart, et il n'y en aura pas d'autre.
#
# Posé dans `Scope#filtered`, un filtre irrigue d'un coup la page d'ensemble,
# les axes, les agents, le tableau croisé et l'export — sans un seul appel
# supplémentaire ailleurs.
class Service::Ticket::Statistics::AxisFilter
  Axes   = Service::Ticket::Statistics::Axes
  Values = Service::Ticket::Statistics::Values

  attr_reader :name, :values

  # Deux entrées portant le même axe doivent être RÉUNIES, pas appliquées l'une
  # après l'autre : deux `where` successifs produiraient une intersection, donc
  # zéro ticket, là où l'utilisateur a coché deux valeurs du même champ en
  # attendant de voir les deux.
  def self.normalize(filters)
    Array(filters).each_with_object({}) do |filter, merged|
      entry = filter.respond_to?(:to_h) ? filter.to_h : filter
      name  = entry[:name] || entry['name']
      next if name.blank?

      values = Array(entry[:values] || entry['values'])
      (merged[name.to_s] ||= []).concat(values)
    end.filter_map do |name, values|
      # Une liste vide n'est pas une contrainte impossible mais une absence de
      # contrainte : `WHERE col IN ()` ne renverrait jamais rien.
      #
      # `empty?` et non `any?` : sans bloc, `any?` teste la VÉRACITÉ des
      # éléments, donc `[nil].any?` est faux. Le filtre « non renseigné » —
      # justement porté par un nil — était silencieusement jeté, et la page
      # affichait tous les tickets en prétendant n'en montrer qu'une partie.
      new(name:, values:) unless values.empty?
    end
  end

  def initialize(name:, values:)
    @name   = name.to_s
    @values = Array(values).uniq
  end

  def apply(relation)
    node       = ::Ticket.arel_table[column]
    conditions = []

    # `empty?` ici aussi : une valeur `false` est une réponse, et `any?` sans
    # bloc la traiterait comme une liste vide.
    conditions << node.in(present_values) unless present_values.empty?
    conditions << unset_condition(node) if unset?

    return relation if conditions.empty?

    relation.where(conditions.reduce(:or))
  end

  private

  # Lève `Axes::UnknownAxis` sur tout ce qui n'est pas un axe déclaré.
  #
  # Volontairement plus strict que `by_axis`, qui se contente d'ignorer un axe
  # inconnu : un graphique manquant se voit à l'écran, alors qu'un FILTRE ignoré
  # gonfle silencieusement tous les chiffres de la page. On ne répond pas à une
  # question qu'on n'a pas comprise.
  def column
    @column ||= Axes.resolve(name)
  end

  def present_values
    @present_values ||= values.reject { |value| Values.unset?(value) }
  end

  def unset?
    values.any? { |value| Values.unset?(value) }
  end

  # « Non renseigné » recouvre NULL et la chaîne vide, exactement comme le fait
  # `Values.merge_unset` à l'affichage. Un filtre qui ne les confondrait pas
  # renverrait moins de tickets que le seau sur lequel on vient de cliquer —
  # écart invisible, et impossible à s'expliquer depuis l'interface.
  #
  # BTRIM n'existe pas pour un booléen : sur une colonne non textuelle la
  # condition se réduit à IS NULL, faute de quoi PostgreSQL lève
  # « function btrim(boolean) does not exist » dès la première case cochée.
  def unset_condition(node)
    is_null = node.eq(nil)
    return is_null if ::Ticket.columns_hash[column]&.type != :string

    is_null.or(Arel::Nodes::NamedFunction.new('BTRIM', [node]).eq(''))
  end
end
