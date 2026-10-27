# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Odice — mise en page des e-mails marqués `.odice-mail` (voir Odice::MailLayout).
Rails.application.config.to_prepare do
  if !Channel::EmailBuild.singleton_class.include?(Odice::MailLayout::EmailBuildHook)
    Channel::EmailBuild.singleton_class.prepend(Odice::MailLayout::EmailBuildHook)
  end
end
