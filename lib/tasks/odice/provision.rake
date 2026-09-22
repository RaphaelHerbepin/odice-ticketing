# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — configuration appliquée au déploiement, de façon idempotente.
#
# Pourquoi une tâche rake et pas un seed :
#   - `db/seeds.rb` porte une liste de seeds EN DUR, donc y ajouter un fichier
#     imposerait de modifier un fichier Zammad ;
#   - il commence par `return if User.any?`, donc ne rejoue jamais sur une base
#     existante : impossible de corriger une valeur après coup.
# Une tâche sous `lib/tasks/` est chargée automatiquement par
# `Zammad::Application.load_tasks` : aucun câblage, aucun fichier Zammad touché.

  # Traductions des libellés propres à Odice.
  #
  # Hors du compteur de version, et rejouées à chaque exécution : ce ne sont pas
  # des réglages qu'un administrateur pourrait vouloir conserver, mais les
  # libellés de l'interface Odice elle-même. Les laisser sous le compteur
  # signifiait qu'aucune traduction ajoutée après la première mise en service
  # n'était jamais appliquée — la page Statistiques restait en anglais.
  #
  # Les fichiers `i18n/*.po` sont gérés par translations.zammad.org et ne
  # doivent pas être édités : on passe donc par les traductions personnalisées,
  # stockées en base et prioritaires sur celles du code.
  def odice_translations!
    {
        'Statistics'                  => 'Statistiques',
        '7 days'                      => '7 jours',
        '30 days'                     => '30 jours',
        '90 days'                     => '90 jours',
        '12 months'                   => '12 mois',
        'Tickets created'             => 'Tickets créés',
        'Still open'                  => 'Encore ouverts',
        'Escalated'                   => 'En escalade',
        'Average first response'      => 'Délai moyen de première réponse',
        'Average time to close'       => 'Délai moyen de clôture',
        'First response in time'      => 'Première réponse dans les délais',
        'Closed in time'              => 'Clôturés dans les délais',
        'Created and closed over time' => 'Créations et clôtures dans le temps',
        'By service'                  => 'Par service',
        'By organization'             => 'Par organisation',
        'By state'                    => 'Par état',
        'By priority'                 => 'Par priorité',
        'By agent'                    => 'Par agent',
        'By channel'                  => 'Par canal',
        'No data for this period.'    => 'Aucune donnée sur cette période.',
    }.each do |source, target|
      translation = ::Translation.find_or_initialize_by(locale: 'fr-fr', source: source)
      next if translation.persisted? && translation.target == target

      translation.target = target
      translation.is_synchronized_from_codebase = false
      translation.save!
    end
  end

namespace :odice do
  desc 'Applique la configuration Odice (branding, locale, logo). Idempotent.'
  task provision: :environment do
    # Les libellés d'abord : ils ne dépendent ni du compteur ni de la locale
    # configurée, et doivent suivre chaque mise à jour de l'image.
    UserInfo.current_user_id = 1
    odice_translations!
    # Sans cela, le frontend continue de servir le catalogue précédent — et la
    # sortie anticipée par le compteur sautait le Rails.cache.clear final.
    Rails.cache.clear
    puts '  traductions Odice enregistrées.'

    target  = ENV.fetch('ODICE_PROVISION_VERSION', '1').to_i
    applied = Setting.get('odice_provision_version').to_i
    forced  = %w[1 true yes].include?(ENV['ODICE_PROVISION_FORCE'].to_s.downcase)

    if applied >= target && !forced
      puts "odice:provision — déjà appliqué (version #{applied}), rien à faire."
      next
    end

    # 1. Couper la suggestion d'image AVANT l'auto-wizard.
    #    `lib/auto_wizard.rb:128` appelle `Service::Image.organization_suggest`,
    #    une requête sortante vers images.zammad.com qui ÉCRASE product_logo —
    #    et qui, sans accès sortant, fait patienter 24 s par utilisateur.
    if %w[1 true yes].include?(ENV['ODICE_DISABLE_IMAGE_BACKEND'].to_s.downcase)
      Setting.set('image_backend', '')
      puts '  image_backend désactivé (évite l’écrasement du logo).'
    end

    # 2. Auto-wizard exécuté ICI, et non dans le conteneur `zammad-init`.
    #    `bin/docker-entrypoint` écrit le fichier dans un conteneur éphémère
    #    dont le répertoire de travail n'est partagé avec personne : le service
    #    Rails ne le verrait jamais.
    if ENV['AUTOWIZARD_JSON'].present? && !Setting.get('system_init_done')
      decoded = Base64.decode64(ENV['AUTOWIZARD_JSON'])

      # Une valeur vide ou malformée ne doit pas interrompre le déploiement :
      # AutoWizard.data ferait un JSON.parse sur le fichier écrit et remonterait
      # une JSON::ParserError qui laisserait l'instance à moitié configurée.
      begin
        JSON.parse(decoded)
        valid = decoded.present?
      rescue JSON::ParserError => e
        warn "  !! AUTOWIZARD_JSON illisible, auto-wizard ignoré : #{e.message}"
        valid = false
      end

      if valid
        relative = ENV['AUTOWIZARD_RELATIVE_PATH'].presence || 'auto_wizard.json'
        Rails.root.join(relative).binwrite(decoded)
        ENV['AUTOWIZARD_RELATIVE_PATH'] = relative
        AutoWizard.setup
        puts '  auto-wizard exécuté.'
      end
    end

    # 3. Réglages de marque et de localisation.
    {
      'product_name'     => ENV['ODICE_PRODUCT_NAME'],
      'organization'     => ENV['ODICE_ORGANIZATION'],
      'fqdn'             => ENV['ZAMMAD_FQDN'],
      'http_type'        => ENV['ZAMMAD_HTTP_TYPE'],
      'locale_default'   => ENV['ODICE_LOCALE_DEFAULT'],
      'timezone_default' => ENV['ODICE_TIMEZONE_DEFAULT'],
    }.compact_blank.each do |name, value|
      next if Setting.get(name).to_s == value

      puts "  #{name}: #{Setting.get(name).inspect} -> #{value.inspect}"
      Setting.set(name, value)
    end

    # 4. Langue de l'interface.
    #    `locale_default` ne s'applique qu'aux utilisateurs SANS préférence
    #    personnelle. L'installation renseigne souvent celle-ci d'après la
    #    langue du navigateur (par ex. « en-gb »), ce qui laisse l'interface en
    #    anglais malgré un défaut français. On aligne donc les comptes dont la
    #    langue n'a pas été choisie délibérément.
    if (locale = ENV['ODICE_LOCALE_DEFAULT'].presence)
      forced  = %w[1 true yes].include?(ENV['ODICE_FORCE_USER_LOCALE'].to_s.downcase)
      updated = 0

      ::User.find_each do |user|
        current = user.preferences[:locale]
        next if current == locale
        # Sans forçage, on ne touche pas à un utilisateur ayant explicitement
        # choisi une autre langue que celle héritée de l'installation.
        next if !forced && current.present? && !current.start_with?('en')

        user.preferences[:locale] = locale
        user.save!
        updated += 1
      end

      puts "  langue de l'interface : #{updated} utilisateur(s) alignés sur #{locale}"
    end

    # 5. Mode d'affichage par défaut.
    #    Zammad n'a AUCUN réglage de thème par défaut : la valeur est purement
    #    individuelle, et son absence signifie « suivre le système ». Les deux
    #    frontends divergeaient donc selon le poste de l'agent. On pose un
    #    défaut clair pour les comptes qui n'ont jamais choisi — chacun reste
    #    libre de prendre le sombre ou le suivi du système dans son profil.
    theme = ENV.fetch('ODICE_DEFAULT_THEME', 'light')
    if theme.present? && theme != 'none'
      aligned = 0
      ::User.find_each do |user|
        next if user.preferences[:theme].present?

        user.preferences[:theme] = theme
        user.save!
        aligned += 1
      end
      puts "  mode d'affichage : #{aligned} compte(s) sans préférence alignés sur « #{theme} »"
    end

    # 6. Logo produit : stocké EN BASE via Store, pas dans l'image.
    #    `public/assets/images/logo.svg` n'est que le repli.
    if (logo_path = ENV['ODICE_LOGO_PATH'].presence)
      path = Rails.root.join(logo_path)
      if path.exist?
        timestamp = Service::SystemAssets::ProductLogo.store(path.binread)
        if timestamp
          Setting.set('product_logo', timestamp)
          puts "  product_logo: enregistré (#{timestamp})."
        else
          warn "  !! logo refusé par ProductLogo.store : #{path}"
        end
      else
        warn "  !! ODICE_LOGO_PATH introuvable : #{path}"
      end
    end

    # 7. Marqueur de version, pour que la tâche ne réécrase pas des réglages
    #    modifiés depuis l'interface d'administration.
    Setting.create_if_not_exists(
      title:       'Odice provisioning version',
      name:        'odice_provision_version',
      area:        'Core',
      description: 'Version du provisionnement Odice déjà appliquée.',
      options:     {},
      state:       0,
      frontend:    false,
    )
    Setting.set('odice_provision_version', target)

    Rails.cache.clear
    puts "odice:provision — version #{target} appliquée."
  end
end
