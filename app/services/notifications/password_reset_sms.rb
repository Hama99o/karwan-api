module Notifications
  # The text of the password-reset message.
  #
  # Separate copy from `OtpSms` even though both carry a six-digit code, and
  # that is deliberate: "your code is 123456" is ambiguous when it could mean
  # either signing in or a reset, and an ambiguous SMS is exactly what a
  # phishing message imitates. A person who did NOT ask for this needs to be
  # able to tell from the message what it is for.
  class PasswordResetSms
    PLACEHOLDER = "%{code}".freeze
    FALLBACK = "Karwan: use %{code} to set a new password. If you did not ask for this, ignore it.".freeze

    def self.body(code:, locale: nil)
      template = Setting.fetch(setting_key(locale))
      template = Setting.fetch("password_reset_sms_body_en") if template.blank?

      unless template.include?(PLACEHOLDER)
        Rails.logger.error("[password_reset] the SMS template for #{locale.inspect} has no #{PLACEHOLDER} — falling back")
        template = FALLBACK
      end

      format(template, code: code)
    end

    def self.setting_key(locale)
      case locale.to_s[0, 2]
      when "ps" then "password_reset_sms_body_ps"
      when "fa" then "password_reset_sms_body_fa"
      else "password_reset_sms_body_en"
      end
    end
  end
end
