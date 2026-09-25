# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # PERSONAL DATA THIS APP ACTUALLY CARRIES (25 Sept 2026, karwan-42's privacy
  # pass): every phone (a customer's, a passenger's, a shop contact's, a
  # guarantor's), a courier's national ID number, the login identifier
  # (a phone or an email), and a one-time code. `code` is matched EXACTLY,
  # so `order_code` and the like stay readable in the logs. The cost, named:
  # Rails applies this list to `Model#inspect` too, so `Order#inspect` in a
  # rails console shows `code: [FILTERED]` (`order.code` still returns it,
  # and the Administrate console reads attributes directly). A reset code in
  # a log is worse.
  :phone, :national_id, /\Aidentifier\z/, /\Acode\z/
]
