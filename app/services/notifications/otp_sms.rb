module Notifications
  # The text of the one-time-code message.
  #
  # ── The server holds this copy, and that is an exception worth naming ─────
  # Everywhere else the server sends i18n KEYS and the app holds the words —
  # the job step list, the problem reasons — because the server cannot write
  # Pashto and a server-written English string is untranslatable on the device.
  #
  # AN SMS HAS NO DEVICE TO TRANSLATE IT. It arrives in the phone's messaging
  # app, and it is the FIRST thing anybody ever reads from this platform. So the
  # copy has to live here — and because it does, it lives in `Setting` rows
  # rather than in Ruby, so Hamma9900 can paste the real Pashto and Dari into
  # the admin console without a deploy.
  #
  # The defaults are English placeholders ON PURPOSE, for the same reason the
  # mobile app's are: a plausible-but-wrong guess at Pashto ships unnoticed,
  # and an obviously untranslated string does not.
  class OtpSms
    # `%{code}` is the only interpolation, and it is checked: copy pasted into
    # the console without it would send a message with no code in it, which
    # nobody would notice until a user called to say the SMS was useless.
    PLACEHOLDER = "%{code}".freeze

    def self.body(code:, locale: nil)
      template = Setting.fetch(setting_key(locale))
      template = Setting.fetch("otp_sms_body_en") if template.blank?

      unless template.include?(PLACEHOLDER)
        Rails.logger.error("[otp] the SMS template for #{locale.inspect} has no #{PLACEHOLDER} — falling back")
        template = DEFINITIONS_FALLBACK
      end

      format(template, code: code)
    end

    DEFINITIONS_FALLBACK = "Karwan: your code is %{code}".freeze

    def self.setting_key(locale)
      case locale.to_s[0, 2]
      when "ps" then "otp_sms_body_ps"
      when "fa" then "otp_sms_body_fa"
      else "otp_sms_body_en"
      end
    end
  end
end
