# The four roles, defined once. `User#active_role` and `UserRole#role` must
# never drift apart — a role that exists in one enum and not the other is a
# switch to a role the user cannot hold.
module Roles
  ALL = { customer: 0, rider: 1, restaurant_owner: 2, admin: 3 }.freeze
end
