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

  Values = Service::Ticket::Statistics::Values

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

  def initialize(from: nil, to: nil, group_ids: nil, organization_ids: nil, axes: nil, interval: nil, axis_filters: nil, compare: false)
    @from             = from || 30.days.ago.beginning_of_day
    @to               = to || Time.zone.now.end_of_day
    @group_ids        = group_ids.presence
    @organization_ids = organization_ids.presence
    @axes             = Array(axes).presence
    @axis_filters     = axis_filters
    @compare          = compare
    @interval         = INTERVALS.key?(interval.to_s) ? interval.to_s : auto_interval
  end

  def execute
    {
      period:           { from:, to:, interval: },
      totals:           totals,
      comparison:       comparison,
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

  # Le périmètre vient de `Scope`, comme pour les statistiques par agent. Le
  # reconstruire ici laissait deux définitions du même périmètre vivre côte à
  # côte : celle-ci appliquait les filtres, celle de `volume_over_time` non.
  def stats_scope
    @stats_scope ||= Service::Ticket::Statistics::Scope.new(
      current_user:, from:, to:, group_ids:, organization_ids:, axis_filters: @axis_filters,
    )
  end

  def scope
    stats_scope.created_in_period
  end

  def totals
    totals_service.call
  end

  def totals_service
    @totals_service ||= Service::Ticket::Statistics::Totals.new(scope: stats_scope)
  end

  # Les mêmes chiffres sur la période immédiatement précédente, de même durée.
  #
  # Les bornes sont inclusives des deux côtés : la période précédente s'arrête
  # donc une seconde avant `from`, sans quoi cet instant appartiendrait aux deux
  # fenêtres et un ticket créé pile à la bascule serait compté deux fois.
  #
  # Un décalage de durée fixe, et non le mois calendaire précédent : « le mois
  # dernier » n'est défini que pour une période qui est justement un mois, et
  # tenter de le deviner marcherait pour septembre en ratant « les 30 derniers
  # jours ». Les bornes retenues sont renvoyées, et l'interface les affiche.
  def comparison
    return unless @compare

    previous_to   = from - 1.second
    previous_from = previous_to - (to - from)

    previous_scope = Service::Ticket::Statistics::Scope.new(
      current_user:, from: previous_from, to: previous_to,
      group_ids:, organization_ids:, axis_filters: @axis_filters,
    )

    Service::Ticket::Statistics::Totals
      .new(scope: previous_scope)
      .comparable
      .merge(from: previous_from, to: previous_to)
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

      { name:, label: Axes.label(name, locale), buckets: count_by_column(column) }
    end
  end

  def count_by_column(column)
    # `arel_table[...]` plutôt qu'une chaîne : la colonne est déjà validée par
    # la liste blanche, mais Arel la cite correctement, ce qui protège aussi
    # des noms de champs personnalisés qui heurteraient un mot réservé SQL.
    node = ::Ticket.arel_table[column]

    # Pas de `limit` en base : la fusion des valeurs non renseignées doit
    # précéder la troncature, sinon NULL et la chaîne vide occupent deux des
    # quinze places avant même d'être reconnues comme une seule et même réponse.
    # Un axe est un `select` : sa cardinalité est bornée par sa liste d'options.
    #
    # Le tri porte trois critères, et non le seul compte : à nombre égal, l'ordre
    # viendrait sinon de la base, qui n'en garantit aucun — deux chargements
    # successifs intervertiraient deux barres sans que rien n'ait changé. Les
    # valeurs non renseignées passent en dernier à égalité : une absence de
    # réponse n'a pas à devancer une vraie valeur en tête de classement.
    counts  = Values.merge_unset(scope.group(node).count)
    buckets = counts
              .sort_by { |value, count| [-count, Values.unset?(value) ? 1 : 0, value.to_s] }
              .first(TOP_N)
              .map { |value, count| { value: value.nil? ? nil : value.to_s, label: humanize_value(value), count: } }

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

  def humanize_value(value)
    Values.humanize(value, locale)
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
      stats_scope.closed_in_period.group(truncated('tickets', 'close_at')).count,
    )
    logged  = bucketize(
      ::Ticket::TimeAccounting
        .where(ticket_id: stats_scope.visible_ids)
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
end
