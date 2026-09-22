# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — téléchargement des statistiques au format Excel.
#
# Contrôleur volontairement mince : il valide ses paramètres et délègue. Il
# n'interroge JAMAIS `::Ticket` lui-même — c'est le service qui passe par
# `TicketPolicy::ReadScope`, et le court-circuiter serait la seule façon de
# créer une fuite de périmètre ici.
class Ticket::StatisticsController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  def download
    export = Service::Ticket::Statistics::Export
             .with_current_user(current_user)
             .execute(from:, to:, axes: params[:axes], axis_filters:,
                      interval: params[:interval], row_axis: params[:row_axis],
                      column_axis: params[:column_axis])

    send_data(
      export[:content],
      filename:    export[:filename],
      type:        ExcelSheet::CONTENT_TYPE,
      disposition: 'attachment',
    )
  rescue Service::Ticket::Statistics::Axes::UnknownAxis => e
    raise Exceptions::UnprocessableContent, e.message
  end

  private

  # Une date illisible est refusée plutôt que ramenée à `nil` : sans cela
  # l'export porterait sur une période que personne n'a demandée, et rien à
  # l'écran ne le dirait.
  def from
    parse_time(params[:from])
  end

  def to
    parse_time(params[:to])
  end

  def parse_time(value)
    return if value.blank?

    Time.zone.parse(value.to_s) || raise(Exceptions::UnprocessableContent, __('Invalid date.'))
  end

  # Les filtres arrivent sous la forme `f.<axe>[]=valeur`, la même convention
  # que l'URL de la page : c'est ce qui garantit qu'un export ne peut pas
  # diverger de ce qui est affiché.
  #
  # Les clés sont arbitraires, mais chacune repasse par `Axes.resolve` dans le
  # service — le rempart est le même qu'en GraphQL, et à un seul endroit.
  def axis_filters
    params.keys
          .select { |key| key.start_with?('f.') }
          .map { |key| { name: key.delete_prefix('f.'), values: Array(params[key]) } }
  end
end
