# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — export Excel des statistiques.
#
# Reproduit ce qui est à l'écran, filtres compris. Passe par les mêmes services
# que la page, donc par `TicketPolicy::ReadScope` : un agent n'exporte jamais
# plus que ce qu'il peut lire.
class Service::Ticket::Statistics::Export < Service::Base
  requires_current_user!

  # Au-delà, le classeur devient un annuaire : dix onglets d'axes suffisent à
  # couvrir ce qu'un tableau de bord montre.
  MAX_AXIS_SHEETS = 10

  def initialize(from: nil, to: nil, axes: nil, axis_filters: nil, interval: nil,
                 row_axis: nil, column_axis: nil)
    @from         = from
    @to           = to
    @axes         = Array(axes).presence || Service::Ticket::Statistics::Axes.names
    @axis_filters = axis_filters
    @interval     = interval
    @row_axis     = row_axis
    @column_axis  = column_axis
  end

  # Renvoie le contenu ET son nom de fichier : `Service::Base` n'expose que
  # `execute` à travers son proxy, donc l'appelant ne peut pas interroger
  # l'instance ensuite.
  def execute
    book = ExcelSheet::Multi.new(title: title, locale: locale)

    add_summary(book)
    add_volume(book)
    add_agents(book)
    add_axes(book)
    add_crosstab(book)

    { content: book.content, filename: filename }
  end

  private

  # Le nom du fichier reste en ASCII : un Content-Disposition accentué demande
  # un encodage RFC 5987 que les clients interprètent diversement.
  def filename
    "statistiques_#{statistics[:period][:from].to_date}_#{statistics[:period][:to].to_date}.xlsx"
  end

  def statistics
    @statistics ||= Service::Ticket::Statistics
                    .with_current_user(current_user)
                    .execute(from: @from, to: @to, axes: @axes, axis_filters: @axis_filters,
                             interval: @interval, compare: true)
  end

  # Un classeur détaché de l'écran doit dire de quoi il parle : la période et
  # les filtres actifs figurent en toutes lettres dès la première cellule.
  def title
    period = "#{statistics[:period][:from].to_date} – #{statistics[:period][:to].to_date}"
    return "#{t('Statistics')} #{period}" if filter_summary.blank?

    "#{t('Statistics')} #{period} — #{filter_summary}"
  end

  def filter_summary
    @filter_summary ||= Array(@axis_filters).filter_map do |filter|
      entry  = filter.respond_to?(:to_h) ? filter.to_h : filter
      name   = entry[:name] || entry['name']
      values = Array(entry[:values] || entry['values'])
      next if name.blank? || values.empty?

      labels = values.map { |value| Service::Ticket::Statistics::Values.humanize(value, locale) }
      "#{Service::Ticket::Statistics::Axes.label(name, locale)} : #{labels.join(', ')}"
    end.join(' ; ')
  end

  def add_summary(book)
    totals     = statistics[:totals]
    comparison = statistics[:comparison] || {}

    rows = [
      [t('Tickets created'), totals[:total], comparison[:total]],
      [t('Still open'), totals[:open], nil],
      [t('Closed'), totals[:closed], nil],
      [t('Escalated'), totals[:escalated], nil],
      [t('Average first response'), totals[:average_first_response_minutes], comparison[:average_first_response_minutes]],
      [t('Average time to close'), totals[:average_close_minutes], comparison[:average_close_minutes]],
      [t('First response in time'), totals[:first_response_in_time_percent], comparison[:first_response_in_time_percent]],
      [t('Closed in time'), totals[:close_in_time_percent], comparison[:close_in_time_percent]],
      [t('Time logged'), totals[:time_logged_minutes], comparison[:time_logged_minutes]],
      [t('Time logging coverage'), totals[:time_coverage_percent], comparison[:time_coverage_percent]],
    ]

    book.add_sheet(
      name:    t('Summary'),
      title:   title,
      header:  [
        { name: 'metric', display: t('Indicator'), width: 34 },
        { name: 'value', display: t('Value'), width: 14 },
        { name: 'previous', display: t('Preceding period'), width: 18 },
      ],
      records: rows,
    )
  end

  def add_volume(book)
    book.add_sheet(
      name:    t('Volume'),
      title:   "#{t('Created and closed over time')} (#{statistics[:period][:interval]})",
      header:  [
        { name: 'date', display: t('Period'), width: 14 },
        { name: 'created', display: t('Created'), width: 12 },
        { name: 'closed', display: t('Closed'), width: 12 },
        { name: 'minutes', display: t('Minutes'), width: 12 },
      ],
      records: statistics[:volume_over_time].map do |point|
        [point[:date], point[:created], point[:closed], point[:time_logged_minutes]]
      end,
    )
  end

  def add_agents(book)
    agents = Service::Ticket::Statistics::Agents
             .with_current_user(current_user)
             .execute(from: @from, to: @to, axis_filters: @axis_filters)

    book.add_sheet(
      name:    t('Agents'),
      title:   t('By agent'),
      header:  [
        { name: 'agent', display: t('Agent'), width: 26 },
        { name: 'open', display: t('Open'), width: 10 },
        { name: 'escalated', display: t('Escalated'), width: 12 },
        { name: 'dormant', display: t('Dormant'), width: 12 },
        { name: 'received', display: t('Received'), width: 12 },
        { name: 'closed', display: t('Closed'), width: 12 },
        { name: 'first', display: t('Average first response'), width: 22 },
        { name: 'close', display: t('Average time to close'), width: 22 },
        { name: 'in_time', display: t('Closed in time'), width: 16 },
        { name: 'logged', display: t('Time logged'), width: 14 },
      ],
      records: agents.map do |agent|
        [
          agent[:label], agent[:open], agent[:escalated], agent[:dormant], agent[:received],
          agent[:closed], agent[:average_first_response_minutes], agent[:average_close_minutes],
          agent[:close_in_time_percent], agent[:time_logged_minutes],
        ]
      end,
    )
  end

  def add_axes(book)
    statistics[:by_axis].first(MAX_AXIS_SHEETS).each do |axis|
      book.add_sheet(
        name:    axis[:label],
        title:   axis[:label],
        header:  [
          { name: 'value', display: axis[:label], width: 34 },
          { name: 'count', display: t('Tickets'), width: 12 },
        ],
        records: axis[:buckets].map { |bucket| [bucket[:label], bucket[:count]] },
      )
    end
  end

  # Le croisement n'est exporté que s'il a été demandé : l'ajouter d'office
  # imposerait une agrégation de plus à chaque export.
  def add_crosstab(book)
    return if @row_axis.blank? || @column_axis.blank? || @row_axis == @column_axis

    cross = Service::Ticket::Statistics::Crosstab
            .with_current_user(current_user)
            .execute(row_axis: @row_axis, column_axis: @column_axis,
                     from: @from, to: @to, axis_filters: @axis_filters)

    header = [{ name: 'row', display: cross[:row_axis][:label], width: 30 }]
    cross[:columns].each { |column| header << { name: column[:label], display: column[:label], width: 14 } }
    header << { name: 'total', display: t('Total'), width: 12 }

    records = cross[:rows].map { |row| [row[:label], *row[:cells], row[:total]] }
    records << [t('Total'), *cross[:columns].map { |column| column[:count] }, cross[:total]]

    book.add_sheet(name: t('Cross-tabulation'), title: "#{cross[:row_axis][:label]} × #{cross[:column_axis][:label]}",
                   header:, records:)
  end

  def t(text)
    ::Translation.translate(locale, text)
  end

  def locale
    @locale ||= current_user&.locale.presence || ::Setting.get('locale_default').presence || 'en-us'
  end
end
