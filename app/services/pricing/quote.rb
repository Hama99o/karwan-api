module Pricing
  # What every quote returns: the distance it was priced from, the time it
  # implies, and every amount, already rounded to the minor unit.
  #
  # A struct rather than a Hash so a typo is a NoMethodError at the call site
  # instead of a silent nil that becomes a zero fee.
  Quote = Data.define(:distance_km, :duration_minutes, :currency, :amounts) do
    def to_attributes
      amounts.merge(currency: currency)
    end
  end
end
