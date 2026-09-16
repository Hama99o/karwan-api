module Users
  # ONE FIELD, EITHER IDENTIFIER. Hamma9900: *"login simple with email and
  # password or phone number and password."*
  #
  # ── WHY ONE INPUT AND NOT TWO, OR A TOGGLE ────────────────────────────────
  # Two fields, or a switch between them, is a decision the user has to make
  # and a screen they can get wrong — and `AFGHAN_UX.md` asks for the fewest
  # taps and the fewest choices. So the field accepts whatever they have and
  # the SERVER decides which it is, by shape: an `@` means an email, anything
  # else is a phone number.
  #
  # ── WHY THE SHAPE AND NOT A GUESS ─────────────────────────────────────────
  # `@` is unambiguous. No Afghan phone number contains one and no email
  # address lacks one, so this needs no heuristics and cannot be fooled by a
  # number that looks like an address.
  #
  # There is no Hatiwal precedent for this: `hatiwal-api` authenticates on an
  # email uid through devise_token_auth and has no phone identity at all. The
  # credential and the mailer are Hatiwal's; this part is ours.
  module Identifier
    Resolved = Data.define(:kind, :value) do
      def email?
        kind == :email
      end

      def phone?
        kind == :phone
      end
    end

    class << self
      # Nil when there is nothing to resolve. A blank identifier is a
      # validation message, not an exception.
      def resolve(raw)
        input = raw.to_s.strip
        return nil if input.blank?

        return Resolved.new(kind: :email, value: input.downcase) if input.include?("@")

        normalised = PhoneNumbers.normalise(input)
        return nil if normalised.blank?

        Resolved.new(kind: :phone, value: normalised)
      end

      # The one account this identifier names, or nil.
      #
      # NORMALISED BEFORE THE LOOKUP, which is the whole point: `0700000801`
      # and `+93700000801` must find the same row, or the second form silently
      # looks like a stranger.
      def find_user(raw)
        resolved = resolve(raw)
        return nil if resolved.nil?

        scope = User.kept
        resolved.email? ? scope.find_by(email: resolved.value) : scope.find_by(phone: resolved.value)
      end
    end
  end
end
