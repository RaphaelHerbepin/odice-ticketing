# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — neutralise une copie de production restaurée hors production.
#
# Une base de production restaurée localement reste une instance COMPLÈTE : elle
# porte les comptes IMAP des boîtes support, les déclencheurs qui répondent aux
# clients et les automatisations planifiées. Démarrée telle quelle, la copie
# relève les mêmes boîtes que la production (et marque les messages comme lus),
# et peut écrire à de vrais clients.
#
# Cette tâche coupe tout ce qui parle au monde extérieur. Elle ne touche à aucune
# donnée métier : tickets, articles, utilisateurs et organisations sont
# inchangés, seul l'attribut `active` de quelques objets de configuration bascule.

namespace :odice do
  desc 'Neutralise une copie de production (canaux, déclencheurs, automatisations). ODICE_SANDBOX_CONFIRM=1 requis.'
  task sandbox: :environment do
    unless %w[1 true yes].include?(ENV['ODICE_SANDBOX_CONFIRM'].to_s.downcase)
      abort <<~MESSAGE
        odice:sandbox — refus d'exécution.

        Cette tâche désactive les canaux e-mail, les déclencheurs et les
        automatisations. Sur une instance de PRODUCTION, elle interromprait le
        service. Pour confirmer qu'il s'agit bien d'une copie :

          ODICE_SANDBOX_CONFIRM=1 bundle exec rake odice:sandbox
      MESSAGE
    end

    UserInfo.current_user_id = 1

    # 1. Canaux. `NotificationFactory::Mailer` cherche
    #    `Channel.find_by(area: 'Email::Notification', active: true)`
    #    (lib/notification_factory/mailer.rb:164) : les désactiver suffit à
    #    couper les notifications sortantes, la relève IMAP et les canaux
    #    sociaux d'un seul geste.
    channels = Channel.where(active: true)
    puts "  canaux désactivés : #{channels.count} (#{channels.distinct.pluck(:area).sort.join(', ')})"
    channels.update_all(active: false) # rubocop:disable Rails/SkipsModelValidations

    # 2. Déclencheurs — ce sont eux qui envoient l'accusé de réception au client
    #    et qui appellent les webhooks.
    triggers = Trigger.where(active: true)
    puts "  déclencheurs désactivés : #{triggers.count}"
    triggers.update_all(active: false) # rubocop:disable Rails/SkipsModelValidations

    # 3. Automatisations planifiées (relances, escalades, fermetures auto).
    jobs = Job.where(active: true)
    puts "  automatisations désactivées : #{jobs.count}"
    jobs.update_all(active: false) # rubocop:disable Rails/SkipsModelValidations

    # 4. Intégrations de supervision et de téléphonie : elles interrogent — ou
    #    sont interrogées par — des systèmes tiers réels.
    integrations = Setting.where("name LIKE '%\\_integration'").pluck(:name)
    integrations.each { |name| Setting.set(name, false) }
    puts "  intégrations désactivées : #{integrations.size}"

    # 5. FQDN local. Restauré depuis la production, il pointe encore vers
    #    l'instance d'origine : les liens des vues et des e-mails renverraient
    #    vers le serveur de production.
    # `NGINX_PORT` est le port INTERNE du conteneur nginx, pas celui publié sur
    # l'hôte : la pile expose Caddy sur 80. Utiliser 8080 ici produisait un FQDN
    # injoignable, affiché jusque dans le titre de la page de connexion.
    # `.presence ||` : le fichier compose déclare les variables ODICE_* avec
    # `${VAR:-}`, donc elles existent, vides, et `fetch` ne prendrait jamais son
    # défaut — le FQDN deviendrait la chaîne vide.
    fqdn = ENV['ODICE_SANDBOX_FQDN'].presence || 'localhost'
    # `http_type` ne sert pas qu'à fabriquer des liens : `Session.secure_flag?`
    # le lit pour décider de poser l'attribut Secure sur le cookie de session.
    # Le forcer à `http` derrière une terminaison TLS produirait donc des liens
    # en clair ET un cookie sans Secure. D'où une variable, avec `http` par
    # défaut — le cas d'une copie servie en local, inchangé.
    http_type = ENV['ODICE_SANDBOX_HTTP_TYPE'].presence || 'http'
    Setting.set('fqdn', fqdn)
    Setting.set('http_type', http_type)
    puts "  fqdn → #{http_type}://#{fqdn}"

    # 6. Accès local. Une instance authentifiée par SSO n'affiche pas le
    #    formulaire de connexion (`user_show_password_login` à false), et son
    #    fournisseur d'identité refuserait de toute façon une redirection vers
    #    localhost : l'URL de rappel enregistrée côté fournisseur est celle de
    #    la production. Sans ce réglage, la copie est inaccessible.
    Setting.set('user_show_password_login', true)
    providers = Setting.where("name LIKE 'auth\\_%'")
                       .pluck(:name)
                       .select { |n| n != 'auth_third_party_auto_link_at_inital_login' && Setting.get(n) == true }
    providers.each { |name| Setting.set(name, false) }
    puts "  connexion par mot de passe activée ; fournisseurs SSO désactivés : #{providers.join(', ').presence || 'aucun'}"

    # Mot de passe de secours : un compte créé par SSO n'en a pas d'utilisable.
    if (password = ENV['ODICE_SANDBOX_PASSWORD']).present?
      admins = User.joins(:roles).where(roles: { name: 'Admin' }, users: { active: true }).distinct
      admins.each { |admin| admin.update!(password:, verified: true) }
      puts "  mot de passe appliqué à #{admins.count} compte(s) administrateur."
    end

    # 7. Le nom du produit n'est plus suffixé ici.
    #
    #    Il l'était par « — COPIE », ce qui alourdissait chaque titre de page
    #    pour redire ce qu'ODICE_PRODUCT_NAME porte déjà — « Odice Helpdesk
    #    (staging) ». La distinction visible entre les deux instances est
    #    désormais assurée par un bandeau permanent dans l'interface, qui se
    #    voit bien mieux qu'un suffixe en fin de titre.
    #
    #    On retire le suffixe s'il subsiste d'une exécution précédente.
    Setting.set('product_name', Setting.get('product_name').to_s.sub(/ — COPIE\z/, ''))

    Rails.cache.clear
    puts 'odice:sandbox — copie neutralisée.'
  end
end
