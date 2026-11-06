# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — création de tickets par clé API (connecteurs MCP, scripts).
#
# Problème : les champs « agence », « service_demandeur » et « it_categorie »
# sont obligatoires dans le formulaire, et Zammad applique aussi cette règle
# aux appels API. Un connecteur dont l'outil de création n'accepte pas les
# champs personnalisés ne peut donc jamais créer de ticket.
#
# Ce module, limité aux créations faites avec une clé API (jeton d'accès) :
# 1. complète ce qui peut l'être de façon fiable :
#    - agence : organisation du demandeur si elle correspond à une agence,
#      sinon l'agence de son dernier ticket ;
#    - service_demandeur : celui de son dernier ticket ;
#    - it_categorie : « Divers » pour un ticket IT sans catégorie ;
# 2. ne bloque pas la création si un champ reste vide (comme pour un ticket
#    arrivé par e-mail) : le connecteur peut le renseigner ensuite avec la
#    mise à jour, qui accepte les champs personnalisés.
#
# Rien ne change pour l'interface (navigateur), les e-mails, ni les mises à
# jour. Une valeur fournie n'est jamais remplacée.
module Odice::TicketChampsDefaut
  extend ActiveSupport::Concern

  included do
    # prepend : avant la validation Core Workflow (aussi en before_create)
    before_create :odice_champs_par_defaut, prepend: true
    prepend Odice::TicketChampsDefaut::Validation
  end

  module Validation
    private

    # ChecksCoreWorkflow#check_mandatory : ignoré pour une création par clé API
    def check_mandatory(perform_result)
      return if odice_creation_par_cle_api?

      super
    end
  end

  private

  def odice_creation_par_cle_api?
    new_record? && screen.present? && UserInfo.current_token.present?
  end

  def odice_champs_par_defaut
    return if !odice_creation_par_cle_api?

    client = customer || (customer_id && User.find_by(id: customer_id))
    if client
      odice_completer(:agence) { odice_agence_organisation(client) || odice_valeur_precedente(client, :agence) }
      odice_completer(:service_demandeur) { odice_valeur_precedente(client, :service_demandeur) }
    end
    odice_completer(:it_categorie) { 'Divers' if !has_attribute?(:service_concerne) || self[:service_concerne].blank? || self[:service_concerne] == 'IT' }
  end

  def odice_completer(champ)
    return if !has_attribute?(champ)
    return if self[champ].present?

    valeur = yield
    self[champ] = valeur if valeur.present?
  end

  def odice_agence_organisation(client)
    org = organization || client.organization
    return if !org

    nom = org.name.to_s.strip
    options = ObjectManager::Attribute.get(object: 'Ticket', name: 'agence')&.data_option&.dig('options') || {}
    options.keys.find { |k| k.to_s.casecmp?(nom) } ||
      options.find { |_k, v| v.to_s.casecmp?(nom) }&.first
  end

  def odice_valeur_precedente(client, champ)
    Ticket.where(customer_id: client.id).where.not(champ => [nil, '']).order(created_at: :desc).pick(champ)
  end
end
