# ONE CANONICAL FORM FOR A PHONE NUMBER, because the phone is an identity.
#
# `0700000801` and `+93700000801` are the same person. If the unique index does
# not know that, the second one gets a SECOND ACCOUNT — with its own orders,
# its own wallet and no way to merge them, because a merge would have to decide
# which history is real.
#
# So every number is normalised before it is stored and before it is looked up.
# The normalising is deliberately dull: strip what people type for readability,
# convert the two ways of writing a country code, and assume Afghanistan when
# there is none.
module PhoneNumbers
  DEFAULT_COUNTRY_CODE = "+93".freeze

  # Spaces, dashes and brackets are how humans write numbers and mean nothing
  # to a lookup.
  DECORATION = /[\s\-().]/

  class << self
    # Returns E.164-ish (`+93...`) or nil. Never raises: a malformed number is
    # a validation failure, not an exception, and it arrives from a text field.
    def normalise(raw)
      digits = raw.to_s.strip.gsub(DECORATION, "")
      return nil if digits.blank?

      # `0093...` is the same as `+93...` — both are how a country code is
      # written, and which one appears depends on the keypad somebody used.
      digits = "+#{digits[2..]}" if digits.start_with?("00")
      return digits if digits.start_with?("+")

      # A LOCAL NUMBER. `0700000801` is what an Afghan user types, and the
      # leading zero is a domestic dialling prefix rather than part of the
      # number — keeping it would make `+930700000801`, which is not a number
      # anybody can ring.
      "#{DEFAULT_COUNTRY_CODE}#{digits.delete_prefix('0')}"
    end

    # Loose on purpose. The SERVER is not the place to decide that a number is
    # impossible: a client that refuses a number this accepts is a user who
    # cannot sign in at all, and Afghan numbering has more shapes than any
    # regex here would admit.
    def plausible?(raw)
      normalised = normalise(raw)
      normalised.present? && normalised.match?(/\A\+\d{8,15}\z/)
    end
  end
end
