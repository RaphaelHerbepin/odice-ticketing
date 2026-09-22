# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — périmètre commun à toutes les agrégations statistiques.
#
# Le périmètre est TOUJOURS restreint par `TicketPolicy::ReadScope` : un agent
# ne voit que les statistiques des tickets auxquels il a accès. Ne jamais
# interroger `::Ticket` directement dans les services de statistiques.
#
# Trois relations, et non une seule, parce que « les tickets de la période » ne
# veut pas dire la même chose selon la question posée :
#
#   - combien en avons-nous reçu ?      → `created_in_period`
#   - combien en avons-nous traité ?    → `closed_in_period`
#   - combien en avons-nous sur les bras ? → `open_now`
#
# Les confondre produit des chiffres qui ne se recoupent pas d'un écran à
# l'autre, sans qu'on comprenne pourquoi.
class Service::Ticket::Statistics::Scope
  attr_reader :current_user, :from, :to, :group_ids, :organization_ids

  def initialize(current_user:, from: nil, to: nil, group_ids: nil, organization_ids: nil)
    @current_user     = current_user
    @from             = from || 30.days.ago.beginning_of_day
    @to               = to || Time.zone.now.end_of_day
    @group_ids        = group_ids.presence
    @organization_ids = organization_ids.presence
  end

  # Flux entrant : tickets créés dans la fenêtre.
  def created_in_period
    @created_in_period ||= filtered.where(created_at: from..to)
  end

  # Flux sortant : tickets clôturés dans la fenêtre, quelle que soit leur date
  # de création. Un ticket ouvert l'an dernier et clos ce mois-ci compte ici, et
  # pas dans `created_in_period` — c'est bien le même travail, vu autrement.
  def closed_in_period
    @closed_in_period ||= filtered.where(close_at: from..to)
  end

  # Stock : instantané, indépendant de la période. À signaler à l'écran, sans
  # quoi le chiffre paraît ignorer le filtre de dates.
  def open_now
    @open_now ||= filtered.where(state_id: ::Ticket::State.by_category_ids(:open))
  end

  # Les identifiants du périmètre, sous forme de sous-requête. À utiliser tel
  # quel dans un `where(... in: ...)` : un `pluck` chargerait tous les
  # identifiants en mémoire pour les renvoyer aussitôt à la base.
  def visible_ids
    filtered.select(:id)
  end

  private

  def filtered
    @filtered ||= begin
      relation = TicketPolicy::ReadScope.new(current_user).resolve
      relation = relation.where(group_id: group_ids) if group_ids
      relation = relation.where(organization_id: organization_ids) if organization_ids
      relation
    end
  end
end
