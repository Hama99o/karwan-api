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
end
