module Shared
  # The signed-in user, as they see themselves. Shared across roles because it
  # IS the same thing to all of them — unlike an order, which is three
  # different things.
  class UserSerializer < ApplicationSerializer
    fields :id, :phone, :name, :locale

    # WHICH MODE THIS DEVICE IS IN — read from the session that made the
    # request, not from the user, because a merchant's counter tablet and his
    # pocket phone can be in two modes at once.
    #
    # The field name is unchanged, so the app's payload contract is unchanged.
    # It raises rather than sending null when a caller forgets the option: the
    # app treats a missing `active_role` as a malformed session and signs out,
    # which is a far worse failure to debug than a 500 with a sentence in it.
    field :active_role do |_user, options|
      session = options[:session]
      raise ArgumentError, "UserSerializer needs `session:` to say which mode this device is in" if session.nil?

      session.active_role
    end

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
