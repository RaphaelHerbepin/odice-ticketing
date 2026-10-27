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
        <label class="note"><input type="radio" name="note" value="#{value}"#{checked}>
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

  def layout(title, body)
    <<~HTML
      <!doctype html>
      <html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{h(title)} — #{h(Setting.get('product_name'))}</title>
      <style>
        :root { color-scheme: light; }
        body { margin: 0; font-family: system-ui, -apple-system, "Segoe UI", sans-serif; background: #13284a; color: #1c1c1c; }
        main { max-width: 560px; margin: 48px auto; padding: 32px 28px; background: #fff; border-radius: 12px; }
        h1 { margin: 0 0 16px; font-size: 1.3rem; color: #13284a; }
        .notes { display: grid; grid-template-columns: repeat(5, 1fr); gap: 8px; margin: 20px 0; }
        .note { display: flex; flex-direction: column; align-items: center; gap: 4px; padding: 12px 4px; border: 1px solid #c9d1dc; border-radius: 10px; cursor: pointer; text-align: center; }
        .note input { position: absolute; opacity: 0; }
        .note:has(input:checked) { border-color: #13284a; background: #e8eef7; }
        .note:has(input:focus-visible) { outline: 2px solid #2f6fd6; outline-offset: 2px; }
        .chiffre { font-size: 1.5rem; font-weight: 700; color: #13284a; }
        .libelle { font-size: .75rem; line-height: 1.2; color: #4a5565; }
        .champ { display: block; margin: 8px 0 6px; font-size: .9rem; }
        textarea { width: 100%; box-sizing: border-box; padding: 8px; border: 1px solid #c9d1dc; border-radius: 8px; font: inherit; }
        button { margin-top: 16px; width: 100%; padding: 12px; border: 0; border-radius: 8px; background: #13284a; color: #fff; font: inherit; font-weight: 600; cursor: pointer; }
        .erreur { color: #b42318; font-weight: 600; }
        @media (max-width: 420px) { .notes { grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 4px; } .libelle { font-size: .65rem; } }
      </style></head>
      <body><main><h1>#{h(title)}</h1>#{body}</main></body></html>
    HTML
  end
end
