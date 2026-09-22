# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — agrégations statistiques sur les tickets.
#
# Le périmètre est TOUJOURS restreint par `TicketPolicy::ReadScope` : un agent
# ne voit que les statistiques des tickets auxquels il a accès. Ne jamais
# interroger `::Ticket` directement ici.
class Service::Ticket::Statistics < Service::Base
  requires_current_user!

  attr_reader :from, :to, :group_ids, :organization_ids, :axes

  # Nombre maximal de séries renvoyées par axe : au-delà, un graphique devient
  # illisible et la requête coûteuse.
  TOP_N = 15

  def initialize(from: nil, to: nil, group_ids: nil, organization_ids: nil, axes: nil)
    @from             = from || 30.days.ago.beginning_of_day
    @to               = to || Time.zone.now.end_of_day
    @group_ids        = group_ids.presence
    @organization_ids = organization_ids.presence
    @axes             = Array(axes).presence
  end

  def execute
    {
      period:           { from:, to: },
      totals:           totals,
      by_group:         count_by(:group_id, ::Group),
      by_organization:  count_by(:organization_id, ::Organization),
      by_state:         count_by(:state_id, ::Ticket::State),
      by_priority:      count_by(:priority_id, ::Ticket::Priority),
      by_owner:         count_by_owner,
      by_channel:       count_by(:create_article_type_id, ::Ticket::Article::Type),
      by_axis:          by_axis,
      volume_over_time: volume_over_time,
    }
  end

  private

  def scope
    @scope ||= begin
      relation = TicketPolicy::ReadScope.new(current_user).resolve.where(created_at: from..to)
      relation = relation.where(group_id: group_ids) if group_ids
      relation = relation.where(organization_id: organization_ids) if organization_ids
      relation
    end
  end

  def totals
    closed_state_ids = ::Ticket::State.by_category_ids(:closed)

    {
      total:                          scope.count,
      open:                           scope.where.not(state_id: closed_state_ids).count,
      closed:                         scope.where(state_id: closed_state_ids).count,
      escalated:                      scope.where.not(escalation_at: nil).where(escalation_at: ..Time.zone.now).count,
      average_first_response_minutes: average(:first_response_in_min),
      average_close_minutes:          average(:close_in_min),
      # Part des tickets ayant respecté leur objectif de première réponse.
      # `first_response_diff_in_min` est positif quand l'objectif est tenu.
      first_response_in_time_percent: percentage_in_time(:first_response_diff_in_min),
      close_in_time_percent:          percentage_in_time(:close_diff_in_min),
      time_logged_minutes:            time_logged_minutes,
      # La saisie du temps étant facultative, un total seul est trompeur : il
      # paraît mesurer l'effort alors qu'il ne mesure que la part déclarée. Le
      # taux de couverture est donc calculé avec lui, et l'interface a la
      # consigne de ne jamais montrer l'un sans l'autre.
      time_coverage_percent:          time_coverage_percent,
    }
  end

  # `tickets.time_unit` est maintenu à jour par callback à chaque saisie : la
  # somme ne demande aucune jointure avec la table de détail.
  def time_logged_minutes
    value = scope.sum(:time_unit)
    value.to_f.round(1) if value&.positive?
  end

  def time_coverage_percent
    total = scope.count
    return if total.zero?

    ((scope.where(time_unit: 0.001..).count.to_f / total) * 100).round(1)
  end

  def average(column)
    value = scope.where.not(column => nil).average(column)
    value&.to_f&.round(1)
  end

  def percentage_in_time(column)
    measured = scope.where.not(column => nil)
    total    = measured.count
    return if total.zero?

    ((measured.where(column => 0..).count.to_f / total) * 100).round(1)
  end

  # Agrégation générique sur une colonne de clé étrangère, résolue en libellés.
  def count_by(column, model)
    counts = scope.group(column).order(count_all: :desc).limit(TOP_N).count
    labels = label_map(model, counts.keys.compact)

    counts.filter_map do |id, count|
      next if id.nil?

      { id:, label: labels[id] || "##{id}", count: }
    end
  end

  def count_by_owner
    # L'utilisateur 1 est l'utilisateur système : un ticket qui lui est
    # « attribué » n'a en réalité pas de propriétaire.
    counts = scope.where.not(owner_id: 1).group(:owner_id).order(count_all: :desc).limit(TOP_N).count
    users  = ::User.where(id: counts.keys.compact).index_by(&:id)

    counts.filter_map do |id, count|
      next if id.nil?

      { id:, label: users[id]&.fullname.presence || "##{id}", count: }
    end
  end

  # Agrégations sur les axes métier — agence, service, objet de la demande.
  #
  # Ces champs sont des colonnes de `tickets` portant directement le libellé :
  # aucune jointure n'est nécessaire, contrairement aux clés étrangères.
  def by_axis
    return [] if axes.blank?

    axes.filter_map do |name|
      column = begin
        Axes.resolve(name)
      rescue Axes::UnknownAxis
        # Un axe inconnu est ignoré plutôt que fatal : un tableau de bord
        # enregistré peut référencer un champ qu'un administrateur a depuis
        # désactivé, et ce n'est pas une raison pour ne rien afficher.
        next
      end

      { name:, label: Axes.label(name), buckets: count_by_column(column) }
    end
  end

  def count_by_column(column)
    # `arel_table[...]` plutôt qu'une chaîne : la colonne est déjà validée par
    # la liste blanche, mais Arel la cite correctement, ce qui protège aussi
    # des noms de champs personnalisés qui heurteraient un mot réservé SQL.
    node   = ::Ticket.arel_table[column]
    counts = scope.group(node).order(count_all: :desc).limit(TOP_N).count

    buckets = counts.map do |value, count|
      { value: value.nil? ? nil : value.to_s, label: humanize_value(value), count: }
    end

    append_others(buckets)
  end

  # Au-delà de TOP_N, la somme des barres ne fait plus le total : tout
  # pourcentage calculé à partir de l'affichage serait faux. Un seau résiduel
  # explicite vaut mieux qu'un écart silencieux.
  def append_others(buckets)
    shown = buckets.sum { |bucket| bucket[:count] }
    rest  = scope.count - shown
    return buckets if rest <= 0

    buckets << { value: nil, label: ::Translation.translate(locale, 'Others'), count: rest }
  end

  # Les champs arborescents stockent le chemin complet avec « :: » pour
  # séparateur (« Flex::Bug ou erreur ») : illisible sur un graphique, le
  # chevron rend la hiérarchie sans l'expliquer.
  #
  # `nil?` et non `blank?` : un champ booléen à `false` est « blank » au sens
  # de Rails, et serait donc compté comme non renseigné — alors que « non
  # bloquant » est une réponse, pas une absence de réponse.
  def humanize_value(value)
    return ::Translation.translate(locale, 'Not set') if value.nil?

    case value
    when true  then ::Translation.translate(locale, 'yes')
    when false then ::Translation.translate(locale, 'no')
    else value.to_s.gsub('::', ' › ')
    end
  end

  def locale
    current_user&.locale.presence || ::Setting.get('locale_default').presence || 'en-us'
  end

  def label_map(model, ids)
    return {} if ids.empty?

    model.where(id: ids).index_by(&:id).transform_values do |record|
      record.try(:name) || record.try(:fullname) || record.id.to_s
    end
  end

  # Volume créé / clôturé, par jour. Deux requêtes groupées plutôt qu'une
  # boucle sur les jours, pour rester en O(1) requêtes.
  def volume_over_time
    created = scope.group("DATE(tickets.created_at)").count
    closed  = TicketPolicy::ReadScope.new(current_user).resolve
                                     .where(close_at: from..to)
                                     .group('DATE(tickets.close_at)').count

    (from.to_date..to.to_date).map do |date|
      { date: date.iso8601, created: created[date] || 0, closed: closed[date] || 0 }
    end
  end
end
