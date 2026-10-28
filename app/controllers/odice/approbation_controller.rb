# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — page publique de validation d'une demande de matériel par le
# responsable de l'agence (lien de l'e-mail « Une demande attend votre
# validation »). Voir Odice::TicketApprobation.
#
# Comme pour l'enquête, le GET n'enregistre rien (les messageries ouvrent les
# liens pour les analyser) : la décision part au POST. Une décision prise est
# définitive depuis cette page ; le service IT peut ensuite la corriger dans le
# ticket (macros « Approuver / Refuser la demande »).
#
# Effets d'une décision, déclencheurs ACTIFS :
#   - note interne « Demande validée / refusée par … » avec le commentaire ;
#   - champ « Approbation » à Approuvé ou Refusé → déclencheurs 20/22 (validée :
#     agents IT et demandeur) ou 21 (refusée : demandeur) ;
#   - refusée : le ticket est clôturé (sans enquête de satisfaction).
class Odice::ApprobationController < Odice::SatisfactionController
  DECIDEE = %w[Approuvé Refusé].freeze

  # Liste des demandes du responsable : à valider, puis déjà traitées.
  def espace
    email = Odice::TicketApprobation.email_for(params[:token])
    if email.blank?
      render html: layout('Lien invalide', '<p>Ce lien est invalide ou a expiré.</p>').html_safe, status: :not_found # rubocop:disable Rails/OutputSafety
      return
    end

    demandes  = Odice::TicketApprobation.demandes_for(email).where.not(state_id: Ticket::State.by_category_ids(:merged))
    a_valider = demandes.where(approbation: [nil, '', 'En attente']).where.not(state_id: Ticket::State.by_category_ids(:closed))
                        .order(created_at: :asc).limit(100)
    traitees  = demandes.where(approbation: DECIDEE).order(updated_at: :desc).limit(30)

    corps = +"<p>Demandes de matériel dont vous êtes le responsable de validation (#{h(email)}).</p>"
    corps << '<h2 class="section">À valider</h2>'
    corps << (a_valider.any? ? liste(a_valider, actions: true) : '<p class="vide">Aucune demande en attente de votre validation.</p>')
    corps << '<h2 class="section">Déjà traitées</h2>'
    corps << (traitees.any? ? liste(traitees, actions: false) : '<p class="vide">Aucune demande traitée pour l’instant.</p>')
    corps << '<p class="note-bas">Gardez ce lien : il ouvre toujours la liste à jour de vos demandes, sans compte Zammad.</p>'
    render html: layout('Mes demandes de matériel', corps).html_safe # rubocop:disable Rails/OutputSafety
  end

  def show
    ticket = find_demande
    return if !ticket

    render html: demande_page(ticket, choix: params[:decision].to_s).html_safe # rubocop:disable Rails/OutputSafety
  end

  def create
    ticket = find_demande
    return if !ticket

    if DECIDEE.include?(ticket.approbation.to_s)
      render html: demande_page(ticket).html_safe # rubocop:disable Rails/OutputSafety
      return
    end

    valeur = Odice::TicketApprobation::DECISIONS[params[:decision].to_s]
    if !valeur
      render html: demande_page(ticket, erreur: 'Merci de choisir : valider ou refuser.').html_safe, status: :unprocessable_content # rubocop:disable Rails/OutputSafety
      return
    end

    enregistrer(ticket, valeur, params[:commentaire].to_s.strip.first(2000))
    render html: layout('Merci', <<~HTML).html_safe # rubocop:disable Rails/OutputSafety
      <p class="decide #{valeur == 'Approuvé' ? 'ok' : 'ko'}">Votre décision a bien été enregistrée : demande #{valeur == 'Approuvé' ? 'validée' : 'refusée'}.</p>
      <p>#{valeur == 'Approuvé' ? 'Le service IT prend la suite et le demandeur est prévenu.' : 'Le demandeur est prévenu que sa demande n’a pas été validée.'} Vous pouvez fermer cette page.</p>
      #{lien_espace(ticket)}
    HTML
  end

  private

  def find_demande
    ticket = Odice::TicketApprobation.ticket_for(params[:token])
    return ticket if ticket && ticket.try(:it_categorie).to_s == 'Matériel'

    render html: layout('Lien invalide', '<p>Ce lien de validation est invalide ou a expiré.</p>').html_safe, status: :not_found # rubocop:disable Rails/OutputSafety
    nil
  end

  def enregistrer(ticket, valeur, commentaire)
    UserInfo.current_user_id = 1
    qui   = Odice::TicketApprobation.approbateur_for(ticket).presence || 'le responsable de l’agence'
    quand = Time.current.in_time_zone(Setting.get('timezone_default').presence || 'Europe/Paris').strftime('%d/%m/%Y à %H:%M')
    verbe = valeur == 'Approuvé' ? 'validée' : 'refusée'

    corps = +"<p><b>Demande #{verbe}</b> par #{h(qui)} le #{quand}, depuis le lien de validation.</p>"
    corps << "<p>Commentaire : #{h(commentaire).gsub("\n", '<br>')}</p>" if commentaire.present?

    Transaction.execute do
      ticket.with_lock do
        Ticket::Article.create!(
          ticket_id:    ticket.id,
          type:         Ticket::Article::Type.lookup(name: 'note'),
          sender:       Ticket::Article::Sender.lookup(name: 'System'),
          internal:     true,
          content_type: 'text/html',
          subject:      "Validation du responsable : demande #{verbe}",
          body:         corps,
        )
        attrs = { approbation: valeur }
        attrs[:state] = Ticket::State.find_by!(name: 'closed') if valeur == 'Refusé'
        ticket.update!(attrs)
      end
    end
  ensure
    UserInfo.current_user_id = nil
  end

  def lien_espace(ticket)
    url = ticket.odice_espace_approbateur_url
    url.present? ? %(<p class="note-bas"><a href="#{h(url)}">Voir toutes mes demandes de matériel</a></p>) : ''
  end

  def liste(tickets, actions:)
    lignes = tickets.map do |t|
      materiel = [t.try(:mat_type), t.try(:mat_precision)].compact_blank.join(' — ')
      cout     = t.try(:mat_cout_estime).present? ? "#{t.mat_cout_estime} €" : ''
      etat = if actions
               %(<a class="mini-btn" href="#{h(t.odice_approbation_url)}">Valider / refuser</a>)
             elsif t.approbation == 'Approuvé'
               '<span class="badge ok">Validée</span>'
             else
               '<span class="badge ko">Refusée</span>'
             end
      <<~HTML
        <li class="demande">
          <div class="demande-tete"><span class="num">n° #{h(t.number)}</span><span class="date">#{h(t.created_at.in_time_zone('Europe/Paris').strftime('%d/%m/%Y'))}</span></div>
          <div class="demande-titre">#{h(t.title)}</div>
          <div class="demande-info">#{h([t.customer&.fullname, t.try(:agence), materiel, cout].compact_blank.join(' · '))}</div>
          <div class="demande-etat">#{etat}</div>
        </li>
      HTML
    end
    %(<ul class="demandes">#{lignes.join}</ul>)
  end

  def ligne(libelle, valeur)
    valeur.present? ? "<dt>#{h(libelle)}</dt><dd>#{h(valeur)}</dd>" : ''
  end

  def demande_page(ticket, choix: '', erreur: nil)
    materiel = [ticket.try(:mat_type), ticket.try(:mat_precision)].compact_blank.join(' — ')
    cout     = ticket.try(:mat_cout_estime).present? ? "#{ticket.mat_cout_estime} €" : nil
    besoin   = ticket.try(:mat_date_besoin)&.strftime('%d/%m/%Y')
    demandeur = [ticket.customer&.fullname, ticket.organization&.name].compact_blank.join(' — ')

    recap = <<~HTML
      <div class="carte">
        <div class="etiquette">Demande n° #{h(ticket.number)}</div>
        <div class="titre">#{h(ticket.title)}</div>
        <dl>
          #{ligne('Demandeur', demandeur)}
          #{ligne('Agence', ticket.try(:agence))}
          #{ligne('Service', ticket.try(:service_demandeur))}
          #{ligne('Matériel', materiel)}
          #{ligne('Coût estimé', cout)}
          #{ligne('Date de besoin', besoin)}
        </dl>
      </div>
      #{ticket.try(:mat_justification).present? ? "<p class=\"champ\">Justification</p><div class=\"citation\">#{h(ticket.mat_justification)}</div>" : ''}
    HTML

    if DECIDEE.include?(ticket.approbation.to_s)
      etat = ticket.approbation == 'Approuvé' ? %(<p class="decide ok">Cette demande a déjà été validée.</p>) : %(<p class="decide ko">Cette demande a déjà été refusée.</p>)
      return layout('Demande de matériel', recap + etat + '<p>Pour revenir sur cette décision, contactez le service IT.</p>' + lien_espace(ticket))
    end

    ok = choix == 'valider' ? ' checked' : ''
    ko = choix == 'refuser' ? ' checked' : ''
    form = <<~HTML
      #{erreur ? "<p class=\"erreur\">#{h(erreur)}</p>" : ''}
      <form method="post" action="/odice/approbation/#{h(params[:token])}">
        <p class="champ">Votre décision</p>
        <div class="choix">
          <label class="ok"><input type="radio" name="decision" value="valider"#{ok}>✓ Valider</label>
          <label class="ko"><input type="radio" name="decision" value="refuser"#{ko}>✕ Refuser</label>
        </div>
        <label for="commentaire" class="champ">Commentaire pour le service IT (facultatif)</label>
        <textarea id="commentaire" name="commentaire" rows="3" maxlength="2000" placeholder="Motif d’un refus, précision sur le matériel…"></textarea>
        <button type="submit">Envoyer ma décision</button>
      </form>
    HTML
    layout('Une demande attend votre validation', recap + form + lien_espace(ticket))
  end
end
