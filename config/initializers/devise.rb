# Devise, for the ADMIN CONSOLE ONLY.
#
# The mobile API does not use Devise at all: the phone number is the identity
# and an OTP is the login, so there is no password to check and no email uid to
# authenticate against. Everything here concerns a human at a desk in a browser.
Devise.setup do |config|
  config.mailer_sender = ENV.fetch("ADMIN_MAILER_SENDER", "no-reply@karwan.af")

  require "devise/orm/active_record"

  config.case_insensitive_keys = [ :email ]
  config.strip_whitespace_keys = [ :email ]

  config.skip_session_storage = [ :http_auth ]
  config.stretches = Rails.env.test? ? 1 : 12
  config.reconfirmable = true
  config.expire_all_remember_me_on_sign_out = true
  config.password_length = 12..128
  config.reset_password_within = 6.hours
  config.sign_out_via = :delete

  # An admin password is the highest-value credential in the system and this
  # surface is reachable from the open internet.
  config.lock_strategy = :failed_attempts
  config.unlock_keys = [ :time ]
  config.unlock_strategy = :time
  config.maximum_attempts = 10
  config.unlock_in = 1.hour

  # A shared office machine left open is the realistic threat here, not a
  # stolen cookie.
  config.timeout_in = 4.hours

  # No Google sign-in in Karwan, by instruction.
end
