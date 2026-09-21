# The four roles, defined once. `UserSession#active_role`,
# `User#last_active_role` and `UserRole#role` must never drift apart — a role
# that exists in one enum and not the other is a switch to a role the user
# cannot hold.
#
# `courier` is role-neutral on purpose: the same human delivers a meal and
# carries a passenger, with one wallet and one commission. The UI says "rider"
# in the food tab and "driver" in the ride tab; the model says courier and
# stays true for both.
module Roles
  ALL = { customer: 0, courier: 1, merchant_owner: 2, admin: 3 }.freeze

  # WHICH ROLES A PHONE MAY BE IN. Correction 16: there is no admin role in the
  # mobile app, because nothing that can credit a wallet or cancel an order
  # belongs on a device that gets shared or lost — and in a cash business that
  # is not a hypothetical. Admin is the Administrate console, on a laptop, with
  # its own separate `AdminUser` table.
  #
  # So a session may never open in `admin` and may never be switched into it,
  # even by someone who genuinely holds the role.
  MOBILE = ALL.keys.map(&:to_s).freeze - [ "admin" ]

  # ── THE ROLES A STRANGER MUST NOT REACH BY TAPPING ────────────────────────
  #
  # `IDENTITY_AND_ROLES.md` §7: *"Switching into a money-handling role
  # mid-session needs re-authentication, because the wallet, the top-up code and
  # 'close the restaurant' are the most damaging things a stranger holding an
  # unlocked phone can reach."* `CLAUDE.md` correction 18 says the same from the
  # other end: *"choosing a money-handling role at sign-in IS the gate, so a
  # separate in-app PIN is only needed for switching roles INSIDE a session."*
  #
  # `AFGHAN_UX.md` §7 is why it is not hypothetical — *"A phone in a household
  # may be used by several people."*
  #
  # CUSTOMER IS NOT HERE, deliberately. It is the default role, it handles no
  # money of ours, and asking for a password to go back to ordering a kebab is
  # the friction correction 10 spends its whole argument removing.
  MONEY_HANDLING = %w[courier merchant_owner].freeze
end
