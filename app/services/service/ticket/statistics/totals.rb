# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — chiffres d'en-tête d'une période.
#
# Classe simple et non `Service::Base` : elle reçoit un `Scope` déjà construit,
# donc déjà cadré par `TicketPolicy::ReadScope`, et n'a pas besoin de connaître
# l'utilisateur courant.
#
# Extraite de `Service::Ticket::Statistics` parce que la comparaison avec la
# période précédente l'appelle une seconde fois sur des bornes décalées.
# Ré-instancier le service entier recalculerait les répartitions, les axes et
# les trois séries temporelles pour n'en garder que ces dix nombres.
class Service::Ticket::Statistics::Totals
  attr_reader :scope

  def initialize(scope:)
    @scope = scope
  end

  def call
    {
      total:                          total,
      open:                           relation.where.not(state_id: closed_state_ids).count,
      closed:                         relation.where(state_id: closed_state_ids).count,
      escalated:                      relation.where.not(escalation_at: nil).where(escalation_at: ..Time.zone.now).count,
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

  # Sous-ensemble comparable d'une période à l'autre.
  #
  # `open`, `closed` et `escalated` en sont volontairement absents : ce ne sont
  # pas des flux mais des ÉTATS observés aujourd'hui sur une cohorte de
  # création. Les tickets créés le mois dernier ont eu un mois de plus pour être
  # traités ; les comparer à ceux de ce mois-ci annoncerait une amélioration
  # spectaculaire tous les mois, éternellement. Mieux vaut ne rien montrer qu'un
  # chiffre qui décrit autre chose que ce que son libellé annonce.
  def comparable
    call.slice(
      :total,
      :average_first_response_minutes,
      :average_close_minutes,
      :first_response_in_time_percent,
      :close_in_time_percent,
      :time_logged_minutes,
      :time_coverage_percent,
    )
  end

  # Le total sert de dénominateur à plusieurs calculs et de référence au seau
  # « Autres » : sans mémoïsation, la même requête partait trois fois.
  def total
    @total ||= relation.count
  end

  private

  def relation
    @relation ||= scope.created_in_period
  end

  def closed_state_ids
    @closed_state_ids ||= ::Ticket::State.by_category_ids(:closed)
  end

  # `tickets.time_unit` est maintenu à jour par callback à chaque saisie : la
  # somme ne demande aucune jointure avec la table de détail.
  def time_logged_minutes
    value = relation.sum(:time_unit)
    value.to_f.round(1) if value&.positive?
  end

  def time_coverage_percent
    return if total.zero?

    ((relation.where(time_unit: 0.001..).count.to_f / total) * 100).round(1)
  end

  def average(column)
    value = relation.where.not(column => nil).average(column)
    value&.to_f&.round(1)
  end

  def percentage_in_time(column)
    measured = relation.where.not(column => nil)
    count    = measured.count
    return if count.zero?

    ((measured.where(column => 0..).count.to_f / count) * 100).round(1)
  end
end
