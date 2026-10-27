# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — un agent corrige une note interne qu'il a déjà validée.
#
# Règles, toutes vérifiées ici sur l'article lui-même :
#   - note (type « note ») et interne : une réponse envoyée au client ne se
#     réécrit pas après coup ;
#   - écrite par l'agent qui la modifie ;
#   - sur un ticket qu'il a le droit de modifier.
# Pas de limite de temps (choix d'exploitation du 27/10/2026).
#
# Trace : la note porte la mention « ✎ Modifiée le … », et les versions
# précédentes sont conservées dans `preferences['odice_revisions']`.
class Odice::ArticleNotesController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  EDITED_MARK = %r{<p>\s*<em>\s*✎ Modifiée le [^<]*</em>\s*</p>}
  MAX_REVISIONS = 20

  def update
    article = Ticket::Article.find(params[:id])
    check_editable!(article)

    body = params[:body].to_s.gsub(EDITED_MARK, '').strip
    raise Exceptions::UnprocessableContent, __('The note cannot be empty.') if body.gsub(%r{<[^>]*>|&nbsp;}, '').strip.empty?

    previous = article.body
    stamp    = Time.current.in_time_zone(Setting.get('timezone_default').presence || 'Europe/Paris')

    article.body         = "#{body}<p><em>✎ Modifiée le #{stamp.strftime('%d/%m/%Y à %H:%M')}</em></p>"
    article.content_type = 'text/html'
    revisions = Array(article.preferences['odice_revisions'])
    revisions << { 'at' => Time.current.iso8601, 'by_id' => current_user.id, 'body' => previous }
    article.preferences['odice_revisions'] = revisions.last(MAX_REVISIONS)
    article.preferences['odice_edited_at'] = Time.current.iso8601
    article.save!

    render json: { id: article.id, body: article.body }, status: :ok
  end

  def closed_state_ids
    render json: { ids: Ticket::State.by_category_ids(:closed) }, status: :ok
  end

  private

  def check_editable!(article)
    raise Exceptions::Forbidden, __('Only internal notes can be edited.') if article.type&.name != 'note' || !article.internal
    raise Exceptions::Forbidden, __('You can only edit your own notes.') if article.created_by_id != current_user.id
    raise Exceptions::Forbidden if !TicketPolicy.new(current_user, article.ticket).agent_update_access?
  end
end
