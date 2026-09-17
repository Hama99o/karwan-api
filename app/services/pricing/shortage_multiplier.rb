module Pricing
  # THE MANUAL SHORTAGE SWITCH — a storm, or a night with nobody on the road.
  #
  # Hamma9900 was explicit about what makes it legitimate: **it raises the
  # customer's fee AND the courier's pay together.** The customer pays more
  # because the courier is paid more, not because we are. On a normal-tier
  # order the platform takes exactly what it took before; the whole of the
  # uplift reaches the person riding through the storm.
  #
  # It is MANUAL on purpose. Automatic surge needs demand and supply signals
  # nobody has yet in one neighbourhood, and a formula nobody can explain to a
  # customer is the trust problem this platform exists to solve. A human turns
  # it on, and a human turns it off.
  #
  # ── THE ORDER OF OPERATIONS, WHICH IS A PRODUCT DECISION ──────────────────
  #
  #   base → shortage → tier
  #
  # Shortage is a market condition on what the run COSTS; premium is a product
  # uplift on top of whatever it costs. Tier going last is what keeps premium
  # exactly +30% over the same run, storm or no storm — and that property is
  # the reason a fare quoted upfront can be explained at all.
  #
  # ── THE CAP, WHICH IS NOT IN ANYBODY'S REQUIREMENTS ───────────────────────
  #
  # `max_total_multiplier` exists because the admin console has no second pair
  # of eyes. A mistyped 10 where 1.5 was meant must not be able to quote a real
  # customer a 10× fare, and there is nobody standing behind Hamma9900 to catch
  # it before it reaches a phone.
  #
  # **The cap is applied to the SHORTAGE, not to the customer's total**, and
  # that is the part worth reading twice. Capping only the customer side would
  # leave the courier's uplift uncapped — so a mistyped 10 would pay the
  # courier 10× base while the customer paid 2×, and the platform would fund
  # the difference out of a commission that cannot cover it. The failure the
  # cap exists to prevent would have been replaced by a more expensive one.
  # Clamping the shortage keeps `courier_fee <= delivery_fee` true by
  # construction, whatever anybody types.
  module ShortageMultiplier
    NONE = BigDecimal("1")

    # What the console is asking for, before any cap. `1` when the switch is
    # off, so turning the switch off is exactly as safe as typing 1.0 and does
    # not depend on anybody having remembered to reset the number.
    def self.requested
      return NONE unless Setting.fetch("shortage_multiplier_enabled")

      [ Setting.fetch("shortage_multiplier"), NONE ].max
    end

    # What may actually be applied, given what the tier will multiply on top.
    #
    # `tier` is the premium multiplier the customer's fee will also carry, so
    # the cap is enforced on the PRODUCT of the two — which is the number a
    # customer sees — while the value returned is the courier's uplift.
    def self.effective(tier: NONE)
      cap = Setting.fetch("max_total_multiplier")
      tier = BigDecimal(tier.to_s)
      return requested if tier <= 0 || cap <= 0

      [ requested, cap / tier ].min
    end

    # True when the cap bit. Derived rather than stored, so it cannot disagree
    # with the two numbers on the order row.
    def self.capped?(tier: NONE)
      effective(tier: tier) < requested
    end
  end
end
