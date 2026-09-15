module Shared
  # The signed-in user, as they see themselves. Shared across roles because it
  # IS the same thing to all of them — unlike an order, which is three
  # different things.
  class UserSerializer < ApplicationSerializer
    fields :id, :phone, :name, :locale, :active_role

    field :roles do |user|
      user.user_roles.map(&:role)
    end

    view :detailed do
      field :phone_verified do |user|
        user.phone_verified?
      end

      # So the app can show the role switcher only when there is something to
      # switch to. One account, several roles, and the switch must be obvious
      # and fast.
      field :can_switch_roles do |user|
        user.user_roles.size > 1
      end
    end
  end
end
