# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice : filtres par colonne sur les vues de tickets.
#
# Chaque filtre compare la valeur AFFICHÉE dans la colonne (nom complet du client,
# libellé traduit de l'état, chemin « Parent › Enfant » d'une arborescence…) et
# non la valeur stockée : l'agent filtre ce qu'il voit. La comparaison ignore la
# casse et les accents (« raphael » trouve « Raphaël »).
#
# Le filtrage se fait en SQL, sur la requête paginée de la vue : il porte donc sur
# tous les tickets de la vue, pas seulement sur ceux déjà chargés à l'écran.
class Ticket::Overviews::ColumnFilter
  OPERATORS = %w[contains not_contains starts_with ends_with equals not_equals is_empty is_not_empty].freeze
  VALUELESS_OPERATORS = %w[is_empty is_not_empty].freeze

  MAX_FILTERS      = 10
  MAX_VALUE_LENGTH = 255

  # Majuscules incluses : selon la collation de la base, lower() ne les convertit
  # pas toujours.
  ACCENTS = {
    'a' => 'àâäáãåÀÂÄÁÃÅ',
    'c' => 'çÇ',
    'e' => 'éèêëÉÈÊË',
    'i' => 'íìîïÍÌÎÏ',
    'n' => 'ñÑ',
    'o' => 'óòôöõÓÒÔÖÕ',
    'u' => 'úùûüÚÙÛÜ',
    'y' => 'ýÿÝ',
  }.freeze
  ACCENTS_FROM = ACCENTS.values.join.freeze
  ACCENTS_TO   = ACCENTS.map { |plain, accented| plain * accented.length }.join.freeze

  USER_COLUMNS = %w[customer_id owner_id created_by_id updated_by_id].freeze

  # Séparateur des niveaux d'une arborescence, tel que l'affiche le tableau.
  TREE_SEPARATOR = ' › '.freeze

  attr_reader :filters, :locale

  # filters : tableau de { column:, operator:, value: }
  def initialize(filters, locale:)
    @filters = Array(filters).map { |f| f.to_h.symbolize_keys }
    @locale  = locale
  end

  def apply(relation)
    raise Exceptions::UnprocessableContent, __('Too many column filters.') if filters.size > MAX_FILTERS

    filters.reduce(relation) do |memo, filter|
      condition = condition_for(filter)
      condition ? memo.where(Arel.sql(condition)) : memo
    end
  end

  def self.normalize(value)
    value.to_s.unicode_normalize(:nfc).downcase.tr(ACCENTS_FROM, ACCENTS_TO)
  end

  private

  def condition_for(filter)
    operator = filter[:operator].to_s
    raise Exceptions::UnprocessableContent, __('Unknown column filter operator.') if OPERATORS.exclude?(operator)

    value = filter[:value].to_s.strip
    raise Exceptions::UnprocessableContent, __('Column filter value is too long.') if value.length > MAX_VALUE_LENGTH

    # Un filtre textuel sans texte ne filtre rien : on l'ignore plutôt que de
    # vider la vue.
    return if value.empty? && VALUELESS_OPERATORS.exclude?(operator)

    normalized = "translate(lower(COALESCE((#{display_expression(filter[:column].to_s)}), '')), #{quote(ACCENTS_FROM)}, #{quote(ACCENTS_TO)})"
    needle     = self.class.normalize(value)

    case operator
    when 'contains'     then "#{normalized} LIKE #{like(needle, prefix: true, suffix: true)}"
    when 'not_contains' then "#{normalized} NOT LIKE #{like(needle, prefix: true, suffix: true)}"
    when 'starts_with'  then "#{normalized} LIKE #{like(needle, suffix: true)}"
    when 'ends_with'    then "#{normalized} LIKE #{like(needle, prefix: true)}"
    when 'equals'       then "#{normalized} = #{quote(needle)}"
    when 'not_equals'   then "#{normalized} <> #{quote(needle)}"
    when 'is_empty'     then "#{normalized} = ''"
    when 'is_not_empty' then "#{normalized} <> ''"
    end
  end

  # Expression SQL donnant, pour chaque ticket, le texte affiché dans la colonne.
  def display_expression(column)
    name = column.delete_suffix('_id')

    case name
    when 'title', 'number'
      ticket_column(name)
    when 'customer', 'created_by', 'updated_by'
      user_name_expression("#{name}_id")
    when 'owner'
      # Le propriétaire « personne » est l'utilisateur système (id 1).
      "CASE WHEN tickets.owner_id = 1 THEN NULL ELSE #{user_name_expression('owner_id')} END"
    when 'organization'
      '(SELECT organizations.name FROM organizations WHERE organizations.id = tickets.organization_id)'
    when 'group'
      "(SELECT REPLACE(groups.name, '::', #{quote(TREE_SEPARATOR)}) FROM groups WHERE groups.id = tickets.group_id)"
    when 'state'
      label_case('tickets.state_id', Ticket::State.pluck(:id, :name), translate: true)
    when 'priority'
      label_case('tickets.priority_id', Ticket::Priority.pluck(:id, :name), translate: true)
    else
      custom_attribute_expression(column)
    end
  end

  def custom_attribute_expression(column)
    attribute = ObjectManager::Attribute.get(object: 'Ticket', name: column)
    raise Exceptions::UnprocessableContent, __('This column cannot be filtered.') if !attribute || attribute.data_option['relation'].present?

    case attribute.data_type
    when 'input', 'textarea', 'richtext'
      ticket_column(column)
    when 'select'
      label_case(ticket_column(column), select_options(attribute.data_option['options']), translate: attribute.data_option['translate'])
    when 'tree_select'
      "REPLACE(#{ticket_column(column)}, '::', #{quote(TREE_SEPARATOR)})"
    else
      raise Exceptions::UnprocessableContent, __('This column cannot be filtered.')
    end
  end

  # Les options d'une liste sont un hash { clé => libellé } ou un tableau de
  # { value:, name: }.
  def select_options(options)
    case options
    when Hash
      options.to_a
    when Array
      options.map { |option| [option['value'], option['name']] }
    else
      []
    end
  end

  def label_case(expression, pairs, translate:)
    return expression if pairs.empty?

    whens = pairs.map do |key, label|
      label = Translation.translate(locale, label.to_s) if translate
      "WHEN #{quote(key)} THEN #{quote(label)}"
    end

    "CASE #{expression} #{whens.join(' ')} ELSE CAST(#{expression} AS VARCHAR) END"
  end

  def user_name_expression(column)
    first = "NULLIF(TRIM(users.firstname), '')"
    last  = "NULLIF(TRIM(users.lastname), '')"

    name = case Setting.get('user_name_format')
           when 'last_first'       then "CONCAT_WS(' ', #{last}, #{first})"
           when 'last_first_comma' then "CONCAT_WS(', ', #{last}, #{first})"
           else                         "CONCAT_WS(' ', #{first}, #{last})"
           end

    "(SELECT COALESCE(NULLIF(#{name}, ''), users.email) FROM users WHERE users.id = tickets.#{connection.quote_column_name(column)})"
  end

  def ticket_column(column)
    raise Exceptions::UnprocessableContent, __('This column cannot be filtered.') if Ticket.column_names.exclude?(column)

    "tickets.#{connection.quote_column_name(column)}"
  end

  def like(needle, prefix: false, suffix: false)
    escaped = ActiveRecord::Base.sanitize_sql_like(needle)
    quote("#{'%' if prefix}#{escaped}#{'%' if suffix}")
  end

  def quote(value)
    connection.quote(value)
  end

  def connection
    ActiveRecord::Base.connection
  end
end
