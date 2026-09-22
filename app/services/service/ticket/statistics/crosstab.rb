# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — croisement de deux axes métier.
#
# Répond aux questions que les histogrammes ne peuvent pas poser : « quelle
# agence nous envoie le plus de pannes matériel ? », « quel service demande le
# plus de licences ? ».
#
# Le contrat de sortie est POSITIONNEL : `rows[i][:cells][j]` correspond à
# `columns[j]`, et les deux listes portent leur éventuel seau « Autres ». Toute
# divergence entre les deux se verrait immédiatement à l'écran, les totaux
# marginaux étant affichés.
class Service::Ticket::Statistics::Crosstab < Service::Base
  requires_current_user!

  Axes   = Service::Ticket::Statistics::Axes
  Values = Service::Ticket::Statistics::Values

  # Plafond par dimension. Au-delà, le tableau déborde de l'écran bien avant de
  # cesser d'être exact ; le reste est replié dans un seau « Autres ».
  TOP_N = 10

  class SameAxis < StandardError; end

  def initialize(row_axis:, column_axis:, from: nil, to: nil,
                 group_ids: nil, organization_ids: nil, axis_filters: nil)
    @row_axis         = row_axis.to_s
    @column_axis      = column_axis.to_s
    @from             = from || 30.days.ago.beginning_of_day
    @to               = to || Time.zone.now.end_of_day
    @group_ids        = group_ids
    @organization_ids = organization_ids
    @axis_filters     = axis_filters
  end

  def execute
    # Un axe croisé avec lui-même est une diagonale : un histogramme écrit en
    # plus gros, et une page entière pour ne rien apprendre.
    raise SameAxis, "Les deux axes sont identiques : #{@row_axis}" if @row_axis == @column_axis

    counts = tally(Axes.resolve(@row_axis), Axes.resolve(@column_axis))

    row_totals = margin(counts, 0)
    col_totals = margin(counts, 1)

    top_rows, rest_rows = split(row_totals)
    top_cols, rest_cols = split(col_totals)

    {
      row_axis:    { name: @row_axis, label: Axes.label(@row_axis, locale) },
      column_axis: { name: @column_axis, label: Axes.label(@column_axis, locale) },
      columns:     columns(col_totals, top_cols, rest_cols, counts),
      rows:        rows(counts, top_rows, rest_rows, top_cols, rest_cols, row_totals),
      total:       counts.values.sum,
    }
  end

  private

  def scope
    @scope ||= Service::Ticket::Statistics::Scope.new(
      current_user:, from: @from, to: @to,
      group_ids: @group_ids, organization_ids: @organization_ids, axis_filters: @axis_filters,
    ).created_in_period
  end

  # Une seule requête, SANS `LIMIT`.
  #
  # Le top 100 des COUPLES n'est pas le croisement des dix meilleures lignes et
  # des dix meilleures colonnes : il produirait un tableau en dents de scie, où
  # une ligne a trois cellules et sa voisine neuf. Les axes étant des champs à
  # liste, leur cardinalité est bornée par leur définition, et PostgreSQL ne
  # renvoie que les couples réellement présents.
  #
  # `pluck` plutôt que `group(...).count` : avec deux nœuds Arel, les clés du
  # hash renvoyé sont ambiguës.
  def tally(row_column, col_column)
    row_node = ::Ticket.arel_table[row_column]
    col_node = ::Ticket.arel_table[col_column]

    scope
      .group(row_node, col_node)
      .pluck(row_node, col_node, Arel.sql('COUNT(*)'))
      .each_with_object(Hash.new(0)) do |(row, col, count), tallied|
        tallied[[Values.unset_key(row), Values.unset_key(col)]] += count
      end
  end

  # Totaux marginaux par sommation du tableau lui-même. Trois requêtes séparées
  # pourraient ne pas concorder avec les cellules, et l'écart se verrait :
  # les totaux sont affichés en marge.
  def margin(counts, index)
    counts.each_with_object(Hash.new(0)) { |(pair, count), totals| totals[pair[index]] += count }
  end

  # Les plus fournis d'abord ; à égalité, les valeurs non renseignées passent
  # en dernier et le reste par ordre alphabétique — sans quoi l'ordre viendrait
  # de la base, qui n'en garantit aucun.
  def split(totals)
    ordered = totals.sort_by { |value, total| [-total, Values.unset?(value) ? 1 : 0, value.to_s] }
    [ordered.first(TOP_N).map(&:first), ordered.drop(TOP_N).map(&:first)]
  end

  def columns(col_totals, top_cols, rest_cols, counts)
    built = top_cols.map { |value| bucket(value, col_totals[value]) }
    return built if rest_cols.empty?

    built << { value: nil, label: others_label,
               count: counts.sum { |(_row, col), count| rest_cols.include?(col) ? count : 0 } }
  end

  def rows(counts, top_rows, rest_rows, top_cols, rest_cols, row_totals)
    built = top_rows.map do |value|
      {
        value: value.nil? ? nil : value.to_s,
        label: Values.humanize(value, locale),
        total: row_totals[value],
        cells: cells_for(counts, [value], top_cols, rest_cols),
      }
    end

    return built if rest_rows.empty?

    built << {
      value: nil,
      label: others_label,
      total: rest_rows.sum { |value| row_totals[value] },
      cells: cells_for(counts, rest_rows, top_cols, rest_cols),
    }
  end

  # Une cellule par colonne affichée, dans le même ordre — plus, s'il y a
  # débordement, la cellule de coin : le croisement de ce qui déborde EN LIGNE
  # avec ce qui déborde EN COLONNE. C'est celle qu'on oublie, et son oubli fait
  # que la somme du tableau ne fait plus le total, donc que tout pourcentage lu
  # à l'écran est faux.
  def cells_for(counts, rows, top_cols, rest_cols)
    cells = top_cols.map { |col| rows.sum { |row| counts[[row, col]] } }
    return cells if rest_cols.empty?

    cells << rows.sum { |row| rest_cols.sum { |col| counts[[row, col]] } }
  end

  def bucket(value, count)
    { value: value.nil? ? nil : value.to_s, label: Values.humanize(value, locale), count: }
  end

  def others_label
    @others_label ||= ::Translation.translate(locale, 'Others')
  end

  def locale
    @locale ||= current_user&.locale.presence || ::Setting.get('locale_default').presence || 'en-us'
  end
end
