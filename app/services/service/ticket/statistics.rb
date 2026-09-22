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

  # Pas de la série temporelle. La valeur est interpolée dans un DATE_TRUNC —
  # elle ne peut donc PAS venir du client sans passer par cette liste.
  INTERVALS = {
    'day'   => 1.day,
    'week'  => 1.week,
    'month' => 1.month,
  }.freeze

  # Au-delà de ces durées, le pas suivant prend le relais. Un an au jour le jour
  # produit 365 barres larges d'un pixel : le graphique cesse d'être lisible
  # bien avant de cesser d'être exact, et personne ne pense à changer un réglage
  # dont il ignore l'existence. D'où un pas choisi par défaut, et modifiable.
  AUTO_THRESHOLDS = [[45.days, 'day'], [180.days, 'week']].freeze

  attr_reader :interval

  def initialize(from: nil, to: nil, group_ids: nil, organization_ids: nil, axes: nil, interval: nil)
    @from             = from || 30.days.ago.beginning_of_day
    @to               = to || Time.zone.now.end_of_day
    @group_ids        = group_ids.presence
    @organization_ids = organization_ids.presence
    @axes             = Array(axes).presence
    @interval         = INTERVALS.key?(interval.to_s) ? interval.to_s : auto_interval
  end

  def execute
    {
      period:           { from:, to:, interval: },
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

    buckets = merge_unset(counts).map do |value, count|
      { value: value.nil? ? nil : value.to_s, label: humanize_value(value), count: }
    end

    append_others(buckets.sort_by { |bucket| -bucket[:count] })
  end

  # Un champ jamais renseigné vaut NULL ; un champ vidé après coup vaut la
  # chaîne vide. La distinction est un accident du stockage, pas une
  # information : laissées telles quelles, elles produisaient deux barres, dont
  # l'une sans étiquette du tout.
  #
  # `false` n'est pas concerné : un booléen à « non » est une réponse. D'où le
  # test sur `nil` et la chaîne vide, et non sur `blank?`.
  def merge_unset(counts)
    counts.each_with_object({}) do |(value, count), merged|
      key = value.is_a?(::String) && value.strip.empty? ? nil : value
      merged[key] = (merged[key] || 0) + count
    end
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

  # Les noms d'états, de priorités et de canaux sont stockés en anglais et
  # traduits à l'affichage par le catalogue Zammad — c'est ainsi que le reste de
  # l'interface montre « nouveau » et « 2 normale ». Les renvoyer bruts laissait
  # « new », « closed » et « 2 normal » sur une page par ailleurs française.
  #
  # Les noms propres, eux, ne se traduisent pas : un groupe « Informatique » ou
  # une organisation resteraient inchangés de toute façon, le catalogue ne les
  # connaissant pas — `translate` renvoie alors la chaîne d'origine.
  def label_map(model, ids)
    return {} if ids.empty?

    model.where(id: ids).index_by(&:id).transform_values do |record|
      name = record.try(:name) || record.try(:fullname) || record.id.to_s
      ::Translation.translate(locale, name)
    end
  end

  # Pas par défaut, déduit de l'étendue demandée. Voir AUTO_THRESHOLDS.
  def auto_interval
    span = to - from
    AUTO_THRESHOLDS.each { |limit, name| return name if span <= limit }
    'month'
  end

  # Le regroupement se fait dans le fuseau de l'instance, pas en UTC. Sans cela
  # un ticket créé à 1 h du matin à Paris tombe dans la veille : le total reste
  # juste, mais chaque journée est décalée, et l'écart devient visible dès qu'on
  # compare la courbe à une liste de tickets.
  #
  # `interval` est sûr à interpoler : le constructeur ne retient qu'une clé
  # d'INTERVALS. Le fuseau, lui, est échappé — il vient d'un réglage.
  def truncated(table, column)
    zone = ::ActiveRecord::Base.connection.quote(Time.zone.tzinfo.identifier)
    Arel.sql("DATE_TRUNC('#{interval}', (#{table}.#{column} AT TIME ZONE 'UTC' AT TIME ZONE #{zone}))")
  end

  # Volume créé / clôturé et temps saisi, au pas retenu. Trois requêtes
  # groupées plutôt qu'une boucle sur les périodes : le nombre de requêtes ne
  # dépend pas de l'étendue analysée.
  def volume_over_time
    created = bucketize(scope.group(truncated('tickets', 'created_at')).count)
    closed  = bucketize(
      TicketPolicy::ReadScope.new(current_user).resolve
                             .where(close_at: from..to)
                             .group(truncated('tickets', 'close_at')).count,
    )
    logged  = bucketize(
      ::Ticket::TimeAccounting
        .where(ticket_id: visible_ids)
        .where(created_at: from..to)
        .group(truncated('ticket_time_accountings', 'created_at'))
        .sum(:time_unit),
    )

    bucket_starts.map do |start|
      key = start.to_date
      {
        date:                start.to_date.iso8601,
        created:             created[key] || 0,
        closed:              closed[key] || 0,
        time_logged_minutes: logged[key]&.to_f&.round(1) || 0.0,
      }
    end
  end

  # Les périodes vides doivent exister dans la série : sans elles, une semaine
  # sans aucun ticket serait absente de l'axe plutôt que montrée à zéro, et la
  # courbe raconterait une activité continue qui n'a pas eu lieu.
  def bucket_starts
    step   = INTERVALS.fetch(interval)
    cursor = case interval
             when 'week'  then from.beginning_of_week
             when 'month' then from.beginning_of_month
             else from.beginning_of_day
             end

    [].tap do |starts|
      while cursor <= to
        starts << cursor
        cursor += step
      end
    end
  end

  # DATE_TRUNC renvoie un horodatage ; seule la date porte l'information, et
  # c'est elle qui sert de clé commune aux trois séries.
  def bucketize(counts)
    counts.transform_keys { |key| key.to_date }
  end

  # Tous les tickets visibles, sans filtre de date : le temps peut être saisi
  # aujourd'hui sur un ticket ouvert l'an dernier. Sous-requête, jamais `pluck`.
  def visible_ids
    TicketPolicy::ReadScope.new(current_user).resolve.select(:id)
  end
end
