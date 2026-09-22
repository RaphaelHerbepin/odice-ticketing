# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Queries
  class Ticket::Statistics::Axes < BaseQuery
    description 'Business axes available for ticket statistics breakdowns'

    type [Gql::Types::Ticket::Statistics::AxisDefinitionType], null: false

    def self.authorize(_obj, ctx)
      ctx.current_user.permissions?('ticket.agent')
    end

    # The list is derived from ObjectManager::Attribute, so it follows the
    # custom fields an administrator actually defined — no hard-coded catalogue
    # to keep in sync.
    def resolve(...)
      Service::Ticket::Statistics::Axes.available(locale)
    end

    private

    def locale
      context.current_user&.locale.presence || Setting.get('locale_default').presence || 'en-us'
    end
  end
end
