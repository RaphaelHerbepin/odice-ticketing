# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — statistiques par agent.
#
# Trois familles de chiffres, qui n'ont pas la même temporalité et qu'il ne faut
# donc pas mêler à l'écran :
#
#   - le STOCK est un instantané : il ignore la période choisie ;
#   - le FLUX porte sur la période ;
#   - le TEMPS SAISI porte sur la période, mais s'attribue à qui l'a saisi —
#     pas au propriétaire du ticket. Voir `time_logged_by`.
#
# Le nombre de requêtes est constant, quel que soit le nombre d'agents : tout
# est groupé côté base. Une boucle sur les agents produirait N requêtes et
# deviendrait le point chaud de la page dès une dizaine d'agents.
class Service::Ticket::Statistics::Agents < Service::Base
  requires_current_user!

  # Seuil d'inactivité au-delà duquel un ticket est considéré comme dormant.
  # C'est volontairement le même que celui de la relance automatique posée par
  # `odice:provision` : la colonne « dormants » indique donc exactement qui
  # recevra un rappel demain matin.
  DORMANT_AFTER = 3.days

  # L'utilisateur 1 est le compte système : un ticket qui lui est « attribué »
  # n'a en réalité pas de propriétaire.
  SYSTEM_USER_ID = 1

  def initialize(from: nil, to: nil, group_ids: nil, organization_ids: nil, axis_filters: nil)
    @from             = from
    @to               = to
    @group_ids        = group_ids
    @organization_ids = organization_ids
    @axis_filters     = axis_filters
  end

  def execute
    ids = (open_counts.keys + closed_rows.keys + received_counts.keys).uniq
    names = ::User.where(id: ids).index_by(&:id)

    ids.filter_map do |id|
      next if id == SYSTEM_USER_ID

      row = closed_rows[id]

      {
        id:,
        label:                          names[id]&.fullname.presence || "##{id}",
        open:                           open_counts[id] || 0,
        escalated:                      escalated_counts[id] || 0,
        dormant:                        dormant_counts[id] || 0,
        received:                       received_counts[id] || 0,
        closed:                         row ? row[:closed] : 0,
        average_first_response_minutes: row && row[:first_response],
        average_close_minutes:          row && row[:close],
        close_in_time_percent:          row && row[:in_time_percent],
        time_logged_minutes:            time_logged_by[id],
      }
    end.sort_by { |agent| [-agent[:open], agent[:label]] }
  end

  private

  # Construit paresseusement : `current_user` n'est disponible qu'une fois le
  # service entré dans le contexte utilisateur posé par `Service::Base.execute`.
  def scope
    @scope ||= Service::Ticket::Statistics::Scope.new(
      current_user:, from: @from, to: @to, group_ids: @group_ids, organization_ids: @organization_ids,
      axis_filters: @axis_filters,
    )
  end

  def open_counts
    @open_counts ||= scope.open_now.group(:owner_id).count
  end

  def escalated_counts
    @escalated_counts ||= scope.open_now
                               .where.not(escalation_at: nil)
                               .where(escalation_at: ..Time.zone.now)
                               .group(:owner_id).count
  end

  def dormant_counts
    @dormant_counts ||= scope.open_now
                             .where(updated_at: ..DORMANT_AFTER.ago)
                             .group(:owner_id).count
  end

  def received_counts
    @received_counts ||= scope.created_in_period.group(:owner_id).count
  end

  # Un seul passage pour les quatre mesures de flux : les faire séparément
  # multiplierait par quatre le parcours de la même tranche de tickets.
  def closed_rows
    @closed_rows ||= begin
      rows = scope.closed_in_period
                  .group(:owner_id)
                  .pluck(
                    Arel.sql('owner_id'),
                    Arel.sql('COUNT(*)'),
                    Arel.sql('AVG(first_response_in_min)'),
                    Arel.sql('AVG(close_in_min)'),
                    Arel.sql('SUM(CASE WHEN close_diff_in_min >= 0 THEN 1 ELSE 0 END)'),
                    Arel.sql('COUNT(close_diff_in_min)'),
                  )

      rows.to_h do |owner_id, closed, first_response, close, in_time, measured|
        [owner_id, {
          closed:,
          first_response:  first_response&.to_f&.round(1),
          close:           close&.to_f&.round(1),
          in_time_percent: measured.to_i.positive? ? ((in_time.to_f / measured) * 100).round(1) : nil,
        }]
      end
    end
  end

  # Temps saisi, attribué à `created_by_id` — c'est-à-dire à celui qui l'a
  # SAISI, pas au propriétaire du ticket. Un agent peut renseigner du temps sur
  # le ticket d'un collègue ; les deux chiffres répondent à deux questions
  # différentes et ne doivent jamais être additionnés.
  #
  # Le filtrage par périmètre passe par une sous-requête : un `pluck(:id)`
  # chargerait tous les identifiants visibles en mémoire pour les renvoyer
  # aussitôt dans un `IN`.
  def time_logged_by
    @time_logged_by ||= ::Ticket::TimeAccounting
                        .where(ticket_id: scope.visible_ids)
                        .where(created_at: scope.from..scope.to)
                        .group(:created_by_id)
                        .sum(:time_unit)
                        .transform_values { |value| value.to_f.round(1) }
  end
end
