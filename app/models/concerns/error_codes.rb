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
    not_a_mobile_role
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
    item_unavailable invalid_options empty_cart no_vehicle_for_this_order
    cannot_price_order merchant_unavailable
  ].freeze

  # A courier and the job in front of them. `offer_expired` is the one an
  # ordinary courier meets by tapping Accept a second late: the honest sentence
  # is that the job went to somebody else and another will come.
  DISPATCH = %w[
    offer_expired not_your_job cannot_advance wrong_step too_early_to_arrive
  ].freeze

  # ── THE THREE VOCABULARIES A GREP FOR `code: "…"` CANNOT SEE ──────────────
  #
  # Each of these reaches a client as a `code:` built from an expression rather
  # than written inline, so the first version of this file — and the spec that
  # certified it complete — missed every one. Reported from the mobile side as
  # five codes on `me#destroy`; there were twenty-six.
  #
  # DECLARED LITERALLY HERE rather than computed from the source constants, so
  # this file stays a readable published list, and
  # `spec/models/error_codes_spec.rb` asserts each group still equals its
  # source. Drift fails there rather than silently reshaping the list.

  # `Users::AccountDeletion::REASONS` — rendered by `me#destroy` on a 422.
  # Every one is FIXABLE, which is why they are named rather than generic:
  # settle up, finish the job, then delete.
  ACCOUNT_DELETION = %w[
    holding_cash wallet_unsettled live_job live_order merchant_orders_in_flight
  ].freeze

  # `Dispatch::Eligibility::REASONS` — why a courier may not take this job.
  # Fourteen, and a courier meets several of them in an ordinary week.
  ELIGIBILITY = %w[
    no_profile not_approved off_shift wrong_job_kind vehicle_too_small
    too_many_passengers wrong_vehicle_class already_on_a_job stale_location
    too_far no_wallet wallet_blocked insufficient_credit cash_in_hand
  ].freeze

  # A SHOP CORRECTING ITSELF. Its own group rather than folded into ORDERING:
  # these refuse a merchant editing its own record, not a customer placing an
  # order, and a client shows them on a settings screen rather than in a cart.
  MERCHANT_SELF_SERVICE = %w[invalid_opening_hours].freeze

  # Where a thing is. `outside_service_area` and `unroutable` are DIFFERENT
  # answers and must not be collapsed: the first says we do not cover that
  # place, the second says we cover it and could not find a way. A client that
  # treats them alike draws a line to somewhere we have said we do not go.
  GEOGRAPHY = %w[outside_service_area unroutable].freeze

  # The request itself, or the server's own state.
  INFRASTRUCTURE = %w[bad_request not_found bad_platform rate_limited pending_migration].freeze

  ALL = (AUTH + OTP + RESET + ORDERING + DISPATCH + ACCOUNT_DELETION + ELIGIBILITY +
         MERCHANT_SELF_SERVICE + GEOGRAPHY + INFRASTRUCTURE).freeze

  # Reachable by an ordinary person doing an ordinary thing, as opposed to by a
  # malformed request or a switched-off feature. These are the ones that most
  # need a sentence in every locale.
  def self.reachable_in_normal_use
    ALL - OTP - %w[bad_request bad_platform not_found pending_migration registration_invalid]
  end
end
