# ── EVERY MACHINE-READABLE REFUSAL THIS API CAN SEND ───────────────────────
#
# `code:` is the contract that lets a client say something in Pashto. The
# mobile repo's `http.ts` puts it plainly: *"showing the server's English
# sentence to a Pashto user is the failure this exists to prevent."* The
# `error` string is for a developer reading a log; the `code` is what a screen
# branches on.
#
# UNTIL NOW IT HAD NO DECLARATION. Every controller that could refuse something
# wrote its own `code:` inline, so the vocabulary could only be recovered with a
# glob — and it drifted to 35 while the app named 7 and guessed at 3 more. A
# vocabulary that needs a grep to enumerate is a vocabulary with no owner, and
# nineteen of these reached a person as a generic "something went wrong".
#
# Reported by the mobile session as F-77. This constant is the declaration;
# `spec/models/error_codes_spec.rb` holds it to the code in both directions —
# nothing emitted may be undeclared, and nothing declared may be unused.
#
# ADDING ONE: put it here with the sentence a user should see, and tell the
# mobile session. A code with no client word is not a smaller bug than a wrong
# message — it is the same bug, delivered silently.
module ErrorCodes
  # Who you are.
  AUTH = %w[
    unauthorized forbidden invalid_credentials account_unavailable
    already_registered registration_invalid role_not_held phone_required
  ].freeze

  # The OTP path, switched OFF by correction 2. Declared because the code still
  # exists and would answer if it were ever switched on; unreachable today.
  OTP = %w[
    otp_disabled otp_expired otp_invalid otp_not_issued otp_throttled
  ].freeze

  # Password reset.
  RESET = %w[reset_code_invalid reset_invalid reset_throttled].freeze

  # Ordering, and what a customer or merchant may do to an order.
  ORDERING = %w[
    no_merchant merchant_is_a_lead tier_unavailable not_cancellable
    invalid_transition reason_required
  ].freeze

  # A courier and the job in front of them. `offer_expired` is the one an
  # ordinary courier meets by tapping Accept a second late: the honest sentence
  # is that the job went to somebody else and another will come.
  DISPATCH = %w[
    offer_expired not_your_job cannot_advance wrong_step too_early_to_arrive
    wallet_blocked
  ].freeze

  # Where a thing is. `outside_service_area` and `unroutable` are DIFFERENT
  # answers and must not be collapsed: the first says we do not cover that
  # place, the second says we cover it and could not find a way. A client that
  # treats them alike draws a line to somewhere we have said we do not go.
  GEOGRAPHY = %w[outside_service_area unroutable].freeze

  # The request itself, or the server's own state.
  INFRASTRUCTURE = %w[bad_request not_found bad_platform rate_limited pending_migration].freeze

  ALL = (AUTH + OTP + RESET + ORDERING + DISPATCH + GEOGRAPHY + INFRASTRUCTURE).freeze

  # Reachable by an ordinary person doing an ordinary thing, as opposed to by a
  # malformed request or a switched-off feature. These are the ones that most
  # need a sentence in every locale.
  def self.reachable_in_normal_use
    ALL - OTP - %w[bad_request bad_platform not_found pending_migration registration_invalid]
  end
end
