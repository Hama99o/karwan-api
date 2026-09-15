module Notifications
  # SENDING AN SMS — the one thing in v0 that costs money per unit.
  #
  # CLAUDE.md correction 14, exception 1: delivering a text to an Afghan phone
  # needs a carrier or a gateway, there is no self-hosted substitute, and this
  # is "the one true per-unit cost in v0 — which is exactly why OTP send
  # throttling is a billing control, not just a security control." It also says
  # to "keep the sending behind one adapter class so it can be swapped in an
  # afternoon." This is that class.
  #
  # ── Why it was worth extracting from the controller ───────────────────────
  # Delivery was `Rails.logger.info` inline in `Auth::OtpController`. Three
  # things were wrong with that beyond tidiness:
  #
  #   1. There was NO MESSAGE. A code was logged; no text was ever composed. The
  #      first thing a Kabul user ever reads from this platform is that SMS, and
  #      it did not exist.
  #   2. Nothing could be swapped without editing a controller, which is the
  #      opposite of "an afternoon".
  #   3. A misconfigured provider would have failed SILENTLY — the worst
  #      possible shape for a login path, because every user simply never
  #      receives a code and the server looks healthy.
  #
  # ── It fails LOUDLY on misconfiguration, and softly on a bad send ─────────
  # An unknown `SMS_PROVIDER` raises at the first send rather than dropping the
  # message, because "nobody can log in" must not look like "nothing happened".
  # A send that fails at the gateway is reported to the caller, which retries or
  # tells the user — it is not swallowed here.
  class SmsClient
    UnknownProvider = Class.new(StandardError)

    # Delivered, or the reason it was not. A boolean would lose the reason and
    # the reason is what an operator needs at 9pm.
    Result = Struct.new(:delivered, :provider, :error, keyword_init: true) do
      def delivered? = delivered
    end

    ADAPTERS = {
      # The default, and correct for development, test and a demo: it writes
      # the message where a developer can read it and costs nothing. It is NOT
      # correct for production and `Notifications::SmsClient.production_ready?`
      # says so, which the deploy runbook checks.
      "log" => "Notifications::Sms::LogAdapter"
    }.freeze

    def self.provider
      ENV.fetch("SMS_PROVIDER", "log")
    end

    # Is there a real gateway behind this? Deliberately explicit, so shipping
    # with the log adapter is a decision somebody made rather than a default
    # nobody noticed.
    def self.production_ready?
      provider != "log"
    end

    def self.adapter
      name = ADAPTERS[provider] or
        raise UnknownProvider,
              "SMS_PROVIDER=#{provider.inspect} is not one of: #{ADAPTERS.keys.join(', ')}. " \
              "A wrong value here means nobody receives a code, so this refuses rather than dropping the message."

      name.constantize
    end

    def self.deliver(to:, body:)
      adapter.deliver(to: to, body: body)
    end
  end
end
