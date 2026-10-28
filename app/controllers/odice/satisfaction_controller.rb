# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — page publique de l'enquête de satisfaction.
#
# Le GET n'enregistre RIEN : les messageries (Outlook Safe Links, antivirus)
# ouvrent tous les liens d'un e-mail pour les analyser, ce qui voterait cinq
# fois. Le lien présélectionne la note ; c'est le bouton qui l'enregistre (POST).
#
# Pas de session ni de jeton CSRF : la page est anonyme, et le jeton signé de
# l'URL, propre à un ticket, tient ce rôle — un tiers ne peut pas le forger.
class Odice::SatisfactionController < ActionController::Base # rubocop:disable Rails/ApplicationController
  skip_forgery_protection

  LABELS = {
    1 => 'Très insatisfait',
    2 => 'Insatisfait',
    3 => 'Neutre',
    4 => 'Satisfait',
    5 => 'Très satisfait',
  }.freeze

  def show
    ticket = find_ticket
    return if !ticket

    note = params[:note].to_i
    render html: page(ticket, selected: Odice::TicketSatisfaction::NOTES.cover?(note) ? note : ticket.try(:satisfaction_note).to_i).html_safe # rubocop:disable Rails/OutputSafety
  end

  def create
    ticket = find_ticket
    return if !ticket

    note = params[:note].to_i
    if !Odice::TicketSatisfaction::NOTES.cover?(note)
      render html: page(ticket, selected: 0, error: 'Merci de choisir une note de 1 à 5.').html_safe, status: :unprocessable_content # rubocop:disable Rails/OutputSafety
      return
    end

    record(ticket, note, params[:commentaire].to_s.strip.first(2000))
    render html: thanks(ticket).html_safe # rubocop:disable Rails/OutputSafety
  end

  private

  def find_ticket
    ticket = Odice::TicketSatisfaction.enabled? && Odice::TicketSatisfaction.ticket_for(params[:token])
    return ticket if ticket

    render html: layout('Lien invalide', '<p>Ce lien d’enquête est invalide ou a expiré.</p>').html_safe, status: :not_found # rubocop:disable Rails/OutputSafety
    nil
  end

  # Sans déclencheurs ni notifications : la réponse du client ne doit pas
  # relancer l'e-mail de clôture ni prévenir l'agent par une « mise à jour ».
  def record(ticket, note, commentaire)
    UserInfo.current_user_id = ticket.customer_id
    Transaction.execute(disable: %w[Transaction::Trigger Transaction::Notification]) do
      attrs = { satisfaction_note: note.to_s }
      attrs[:satisfaction_commentaire] = commentaire if ticket.respond_to?(:satisfaction_commentaire)
      ticket.update!(attrs)
    end
  ensure
    UserInfo.current_user_id = nil
  end

  def h(text) = ERB::Util.html_escape(text)

  def page(ticket, selected:, error: nil)
    options = LABELS.map do |value, label|
      checked = value == selected ? ' checked' : ''
      <<~HTML
        <label class="note note-#{value}"><input type="radio" name="note" value="#{value}"#{checked}>
          <span class="chiffre">#{value}</span><span class="libelle">#{h(label)}</span></label>
      HTML
    end.join

    body = <<~HTML
      <p>Votre demande <strong>##{h(ticket.number)} — #{h(ticket.title)}</strong> a été clôturée.</p>
      <p>Êtes-vous satisfait de la façon dont elle a été traitée ?</p>
      #{error ? "<p class=\"erreur\">#{h(error)}</p>" : ''}
      <form method="post" action="/odice/satisfaction/#{h(params[:token])}">
        <div class="notes">#{options}</div>
        <label for="commentaire" class="champ">Un commentaire ? (facultatif)</label>
        <textarea id="commentaire" name="commentaire" rows="4" maxlength="2000"></textarea>
        <button type="submit">Envoyer mon avis</button>
      </form>
    HTML
    layout('Votre avis', body)
  end

  def thanks(ticket)
    layout('Merci', <<~HTML)
      <p>Merci, votre avis sur la demande <strong>##{h(ticket.number)}</strong> a bien été enregistré.</p>
      <p>Vous pouvez fermer cette page. Si vous changez d’avis, rouvrez le lien de l’e-mail : la dernière réponse compte.</p>
    HTML
  end

  # Mise en page commune aux pages publiques ODICE (enquête, validation) :
  # même charte que les e-mails (Odice::MailLayout).
  def layout(title, body)
    logo = "#{Setting.get('http_type')}://#{Setting.get('fqdn')}/assets/images/odice-email-logo.png"
    <<~HTML
      <!doctype html>
      <html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
      <meta name="robots" content="noindex">
      <title>#{h(title)} — #{h(Setting.get('product_name'))}</title>
      <style>
        :root { color-scheme: light; }
        * { box-sizing: border-box; }
        body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #eef2f6; color: #414042; line-height: 1.55; }
        main { max-width: 600px; margin: 32px auto; background: #fff; border-radius: 12px; border-top: 5px solid #27a9ce; overflow: hidden; }
        .contenu { padding: 24px 32px 32px; }
        .logo { display: block; width: 150px; height: auto; margin: 4px 0 18px; }
        h1 { margin: 0 0 16px; font-size: 1.4rem; line-height: 1.3; color: #0c3258; }
        p { margin: 0 0 14px; }
        .carte { margin: 4px 0 22px; padding: 16px 18px; background: #f1f5f9; border-left: 4px solid #27a9ce; border-radius: 6px; }
        .carte .etiquette { font-size: .75rem; letter-spacing: .06em; text-transform: uppercase; color: #6e7274; margin: 0 0 4px; }
        .carte .titre { font-size: 1.05rem; font-weight: 700; color: #0c3258; margin: 0 0 8px; }
        .carte dl { display: grid; grid-template-columns: max-content 1fr; gap: 2px 12px; margin: 0; font-size: .92rem; }
        .carte dt { color: #6e7274; } .carte dd { margin: 0; font-weight: 600; }
        .citation { margin: 0 0 18px; padding: 10px 14px; border-left: 3px solid #27a9ce; background: #f1f5f9; white-space: pre-line; font-size: .92rem; }
        .notes { display: grid; grid-template-columns: repeat(5, 1fr); gap: 8px; margin: 20px 0; }
        .note { display: flex; flex-direction: column; align-items: center; gap: 4px; padding: 12px 4px; border: 2px solid transparent; border-radius: 10px; cursor: pointer; text-align: center; color: #fff; }
        .note input, .choix input { position: absolute; opacity: 0; }
        .note-1 { background: #c83433; } .note-2 { background: #e07b39; } .note-3 { background: #e8b931; color: #3a2f00; } .note-4 { background: #62b37f; } .note-5 { background: #2e8b57; }
        .note:has(input:checked) { border-color: #0c3258; box-shadow: 0 0 0 3px #c6dcea; transform: translateY(-2px); }
        .note:has(input:focus-visible), .choix label:has(input:focus-visible) { outline: 2px solid #134c82; outline-offset: 2px; }
        .chiffre { font-size: 1.5rem; font-weight: 800; }
        .libelle { font-size: .72rem; line-height: 1.2; }
        .choix { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin: 8px 0 18px; }
        .choix label { display: block; padding: 14px; border: 2px solid #dde2e4; border-radius: 10px; cursor: pointer; text-align: center; font-weight: 700; }
        .choix .ok:has(input:checked) { border-color: #2e8b57; background: #e5f3eb; color: #1f6b41; }
        .choix .ko:has(input:checked) { border-color: #c83433; background: #fbeaea; color: #9c2423; }
        .champ { display: block; margin: 8px 0 6px; font-size: .9rem; font-weight: 600; }
        textarea { width: 100%; padding: 10px; border: 1px solid #ced4d7; border-radius: 8px; font: inherit; }
        button { margin-top: 16px; width: 100%; padding: 13px; border: 0; border-radius: 8px; background: #134c82; color: #fff; font: inherit; font-weight: 700; cursor: pointer; }
        .erreur { color: #b42318; font-weight: 600; }
        .decide { padding: 14px 16px; border-radius: 8px; font-weight: 600; }
        .decide.ok { background: #e5f3eb; color: #1f6b41; } .decide.ko { background: #fbeaea; color: #9c2423; }
        footer { padding: 16px 32px; font-size: .78rem; color: #6e7274; text-align: center; background: #f7f9fb; }
        @media (max-width: 480px) { main { margin: 0; border-radius: 0; } .contenu { padding: 20px; } .notes { gap: 4px; } .libelle { font-size: .62rem; } }
      </style></head>
      <body><main><div class="contenu">
      <img class="logo" src="#{h(logo)}" alt="Groupe ODICE">
      <h1>#{h(title)}</h1>#{body}
      </div><footer>#{h(Setting.get('product_name'))} · Groupe ODICE</footer></main></body></html>
    HTML
  end
end
