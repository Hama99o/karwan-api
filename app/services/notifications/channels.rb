module Notifications
  # CAN THIS CHANNEL ACTUALLY REACH A PERSON? Asked before telling anyone a
  # code is on its way (karwan-42, 25 Sept 2026: password reset answered
  # `channel: "sms", sent: true` while the only SMS adapter writes to a log,
  # so a customer with no email waited for a message that did not exist).
  #
  # A fact about the CHANNEL, never about an account, so an answer built on
  # it is the same for a real number and an unknown one and opens no
  # existence oracle.
  module Channels
    module_function

    def can_deliver?(channel)
      case channel.to_sym
      when :sms then SmsClient.production_ready?
      # production.rb falls back to SMTP on "localhost" when SMTP_ADDRESS is
      # unset, which would also go nowhere; a non-SMTP method (test, a
      # developer's letter opener) is a deliberate local setup.
      when :email then Rails.application.config.action_mailer.delivery_method != :smtp || ENV["SMTP_ADDRESS"].present?
      else false
      end
    end
  end
end
