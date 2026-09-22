# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Reflects the authorization of the GraphQL statistics queries. The DATA
# perimeter is enforced elsewhere and automatically: the controller goes
# through the services, which all resolve TicketPolicy::ReadScope.
class Controllers::Ticket::StatisticsControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('ticket.agent')
end
