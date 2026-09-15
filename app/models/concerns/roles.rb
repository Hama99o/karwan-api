# The four roles, defined once. `User#active_role` and `UserRole#role` must
# never drift apart — a role that exists in one enum and not the other is a
# switch to a role the user cannot hold.
#
# `courier` is role-neutral on purpose: the same human delivers a meal and
# carries a passenger, with one wallet and one commission. The UI says "rider"
# in the food tab and "driver" in the ride tab; the model says courier and
# stays true for both.
module Roles
  ALL = { customer: 0, courier: 1, merchant_owner: 2, admin: 3 }.freeze
end
