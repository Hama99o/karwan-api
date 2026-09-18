module Shared
  # The signed-in user, as they see themselves. Shared across roles because it
  # IS the same thing to all of them — unlike an order, which is three
  # different things.
  class UserSerializer < ApplicationSerializer
    fields :id, :phone, :name, :locale

    # THE VARIANT, not the original. Nil when they have not set one, which the
    # app already renders as initials or a placeholder.
    field :avatar_url do |user|
      Attachments::PublicUrl.for(user.avatar, variant: :thumb)
    end

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

    # ONLY THE ROLES A PHONE MAY BE IN. An admin holds a fourth role and the app
    # has no admin surface at all (correction 16), so leaving it in put an
    # "admin" entry in the role switcher that leads to an empty tab.
    field :roles do |user|
      user.user_roles.map(&:role) & Roles::MOBILE
    end

    # ── THE MARK THE PROFILE SCREEN SHOWS ────────────────────────────────
    #
    # `docs/design/customer/profile/SPEC.md`: "Status as a mark, not prose — ✓
    # verified, ⚠ needs attention. We already hold `verification_status` on the
    # courier." We did hold it, and `/me` did not serve it, so the screen was
    # blocked on the API. Found by the design-SPEC sweep.
    #
    # NIL FOR ANYBODY WHO IS NOT A COURIER, which is most people — the profile
    # screen shows the mark only when there is something to mark, and a
    # customer has no verification state to be in.
    field :courier_verification_status do |user|
      user.courier_profile&.verification_status
    end

    view :detailed do
      field :phone_verified do |user|
        user.phone_verified?
      end

      # So the app can show the role switcher only when there is something to
      # switch to. One account, several roles, and the switch must be obvious
      # and fast.
      field :can_switch_roles do |user|
        (user.user_roles.map(&:role) & Roles::MOBILE).size > 1
      end
    end
  end
end
