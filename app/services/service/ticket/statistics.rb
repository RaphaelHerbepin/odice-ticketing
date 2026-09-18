# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — agrégations statistiques sur les tickets.
#
# Le périmètre est TOUJOURS restreint par `TicketPolicy::ReadScope` : un agent
# ne voit que les statistiques des tickets auxquels il a accès. Ne jamais
# interroger `::Ticket` directement ici.
class Service::Ticket::Statistics < Service::Base
  requires_current_user!

  attr_reader :from, :to, :group_ids, :organization_ids

  # Nombre maximal de séries renvoyées par axe : au-delà, un graphique devient
  # illisible et la requête coûteuse.
  TOP_N = 15

  def initialize(from: nil, to: nil, group_ids: nil, organization_ids: nil)
    @from             = from || 30.days.ago.beginning_of_day
    @to               = to || Time.zone.now.end_of_day
    @group_ids        = group_ids.presence
    @organization_ids = organization_ids.presence
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
    }
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
