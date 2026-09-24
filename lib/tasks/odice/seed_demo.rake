# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — jeu de données fictives pour le staging.
#
# Remplace la copie de production. Trois raisons de préférer des données
# inventées :
#
#   - la copie duplique l'intégralité du fichier client sur un sous-domaine
#     public, ce qui est une question de sécurité autant que de RGPD ;
#   - elle doit être refaite à chaque rafraîchissement, avec le risque
#     — réel, déjà rencontré — qu'une instance non encore neutralisée écrive
#     aux vrais clients ;
#   - elle occupe deux fois la place sur un serveur qui n'en a pas à revendre.
#
# Ce que ce jeu doit permettre : parcourir l'interface, créer un ticket,
# exercer les statistiques et vérifier les droits. Pas de représenter fidèlement
# l'activité réelle — un staging ne sert pas à ça.
#
# Idempotent : relancer la tâche complète ce qui manque sans rien dupliquer.
#
# Usage :
#   rake odice:seed_demo
#   ODICE_DEMO_TICKETS=60 rake odice:seed_demo

namespace :odice do
  desc 'Crée un jeu de données fictives (champs, comptes, tickets) pour le staging'
  task seed_demo: :environment do
    # Garde-fou : ces données n'ont rien à faire en production, et la tâche
    # crée des comptes dont le mot de passe est écrit en clair plus bas.
    environment = ENV['ODICE_ENVIRONMENT'].to_s
    if environment == 'production'
      abort 'REFUS : ODICE_ENVIRONMENT=production. Ce jeu de données est réservé au staging.'
    end

    UserInfo.current_user_id = 1

    # ── Champs personnalisés ───────────────────────────────────────────────
    #
    # Une base vierge n'a aucun des champs qui structurent l'activité d'Odice :
    # sans eux, ni le formulaire de ticket ni les statistiques par axe n'ont de
    # sens. On les recrée avec des valeurs FICTIVES — le staging ne doit pas
    # porter la liste réelle des agences.
    attributes = {
      'agence'            => {
        display: 'Agence',
        options: %w[AGENCE\ NORD AGENCE\ SUD AGENCE\ EST AGENCE\ OUEST].index_with { |value| value },
      },
      'service_demandeur' => {
        display: 'Service du demandeur',
        options: ['Administratif', 'Commercial', 'Informatique', 'Logistique', 'Production'].index_with { |value| value },
      },
      'service_concerne'  => {
        display: 'Service concerné',
        options: { 'IT' => 'IT', 'Généraux' => 'Généraux' },
      },
      'it_bloquant'       => { display: 'Bloquant', data_type: 'boolean', options: { true => 'oui', false => 'non' } },
    }

    attributes.each do |name, spec|
      ObjectManager::Attribute.add(
        object:        'Ticket',
        name:          name,
        display:       spec[:display],
        data_type:     spec[:data_type] || 'select',
        data_option:   {
          options:    spec[:options],
          default:    '',
          null:       true,
          relation:   '',
          maxlength:  255,
          nulloption: true,
        },
        editable:      true,
        active:        true,
        screens:       {
          create_middle: { '-all-' => { shown: true, required: false } },
          edit:          { '-all-' => { shown: true, required: false } },
        },
        position:      200,
        created_by_id: 1,
        updated_by_id: 1,
      )
    end

    # Le champ arborescent se déclare à part : sa structure est imbriquée.
    ObjectManager::Attribute.add(
      object:        'Ticket',
      name:          'it_categorie',
      display:       'Objet de la demande',
      data_type:     'tree_select',
      data_option:   {
        options:    [
          { 'name' => 'Matériel', 'value' => 'Matériel' },
          { 'name' => 'Logiciel', 'value' => 'Logiciel',
            'children' => [
              { 'name' => 'Installation', 'value' => 'Logiciel::Installation' },
              { 'name' => 'Panne', 'value' => 'Logiciel::Panne' },
            ] },
          { 'name' => 'Accès', 'value' => 'Accès',
            'children' => [
              { 'name' => 'Création de compte', 'value' => 'Accès::Création de compte' },
              { 'name' => 'Mot de passe', 'value' => 'Accès::Mot de passe' },
            ] },
        ],
        default:    '',
        null:       true,
        nulloption: true,
      },
      editable:      true,
      active:        true,
      screens:       {
        create_middle: { '-all-' => { shown: true, required: false } },
        edit:          { '-all-' => { shown: true, required: false } },
      },
      position:      210,
      created_by_id: 1,
      updated_by_id: 1,
    )

    ObjectManager::Attribute.migration_execute if ObjectManager::Attribute.migration_execute?
    puts "  #{attributes.size + 1} champs personnalisés en place."

    # ── Comptes ────────────────────────────────────────────────────────────
    #
    # Un compte par rôle : c'est ce qui permet de vérifier qu'un agent ne voit
    # pas ce que voit un administrateur, et qu'un client ne voit que ses
    # propres tickets. Le mot de passe est commun et volontairement trivial —
    # ces comptes n'existent que sur une instance de démonstration, isolée.
    password = ENV['ODICE_DEMO_PASSWORD'].presence || 'demo-odice-2026'
    group    = Group.find_by(name: 'Users') || Group.first

    comptes = [
      { email: 'admin.demo@odice.test',   firstname: 'Alex',    lastname: 'Dubois',   roles: %w[Admin Agent] },
      { email: 'agent1.demo@odice.test',  firstname: 'Camille', lastname: 'Renard',   roles: %w[Agent] },
      { email: 'agent2.demo@odice.test',  firstname: 'Dominique', lastname: 'Leroy',  roles: %w[Agent] },
      { email: 'client1.demo@odice.test', firstname: 'Claude',  lastname: 'Martin',   roles: %w[Customer] },
      { email: 'client2.demo@odice.test', firstname: 'Sacha',   lastname: 'Bernard',  roles: %w[Customer] },
    ]

    users = comptes.map do |compte|
      user = User.find_by(email: compte[:email]) || User.new(email: compte[:email], login: compte[:email])
      user.assign_attributes(
        firstname: compte[:firstname],
        lastname:  compte[:lastname],
        active:    true,
        verified:  true,
        password:  password,
        roles:     Role.where(name: compte[:roles]),
      )
      user.group_ids = [group.id] if compte[:roles].include?('Agent') && group
      user.save!
      user
    end
    puts "  #{users.size} comptes de démonstration (mot de passe : #{password})."

    # ── Tickets ────────────────────────────────────────────────────────────
    #
    # Répartis dans le temps et sur tous les axes, sans quoi les statistiques
    # n'auraient rien à montrer : une page de graphiques vides ne permet pas de
    # vérifier grand-chose.
    cible = (ENV['ODICE_DEMO_TICKETS'].presence || '40').to_i
    agents    = users.select { |u| u.role_ids.intersect?(Role.where(name: 'Agent').ids) }
    customers = users.select { |u| u.role_ids.intersect?(Role.where(name: 'Customer').ids) }

    etats     = Ticket::State.where(name: %w[new open closed]).to_a
    priorites = Ticket::Priority.all.to_a
    agences   = attributes['agence'][:options].keys
    services  = attributes['service_demandeur'][:options].keys
    objets    = ['Matériel', 'Logiciel::Installation', 'Logiciel::Panne', 'Accès::Mot de passe', nil]

    existants = Ticket.where('title LIKE ?', '[démo]%').count
    (cible - existants).clamp(0, cible).times do |i|
      cree_le = rand(1..80).days.ago
      etat    = etats.sample
      ticket  = Ticket.create!(
        title:             "[démo] Demande #{existants + i + 1}",
        group:             group,
        customer:          customers.sample,
        owner:             etat.name == 'new' ? User.find(1) : agents.sample,
        state:             etat,
        priority:          priorites.sample,
        created_at:        cree_le,
        updated_at:        cree_le + rand(0..48).hours,
        agence:            agences.sample,
        service_demandeur: services.sample,
        service_concerne:  'IT',
        it_categorie:      objets.sample,
        it_bloquant:       [true, false].sample,
      )

      # Un ticket sans article n'existe pas vraiment côté interface : il ne
      # s'ouvre pas et fausse les délais de première réponse.
      Ticket::Article.create!(
        ticket:       ticket,
        type:         Ticket::Article::Type.find_by(name: 'note'),
        sender:       Ticket::Article::Sender.find_by(name: 'Customer'),
        from:         ticket.customer.fullname,
        subject:      ticket.title,
        body:         'Message de démonstration. Ces données sont fictives.',
        internal:     false,
        content_type: 'text/plain',
        created_at:   cree_le,
        updated_at:   cree_le,
      )

      next unless etat.name == 'closed'

      ticket.update!(close_at: cree_le + rand(1..72).hours)
    end

    puts "  #{Ticket.where('title LIKE ?', '[démo]%').count} tickets de démonstration."
    Rails.cache.clear
    puts 'odice:seed_demo — jeu de données fictives en place.'
  end
end
