# WHAT THE CUSTOMER AGREED TO, defined once for both demand types.
#
# `docs/SERVICE_TIERS_AND_BATCHING.md` §1. The tier is not a quality level — it
# is a CONSENT: choosing `normal` and paying less is how a customer agrees that
# the courier may combine their job with others.
#
#   premium — this job alone on the run. Costs more.
#   normal  — may be combined with up to `batch_max_jobs` in total. Cheaper.
#
# The same words serve a delivery and a ride: for a ride, `normal` consents to
# another passenger sharing the car and `premium` means the car is theirs.
module ServiceTiers
  ALL = { normal: 0, premium: 1 }.freeze

  # Whether a job of this tier may EVER share a run. It is a property of the
  # tier alone, which is what makes "we simply never batch" a true and cheap
  # way to honour the column before batching exists.
  def self.batchable?(tier)
    tier.to_s == "normal"
  end
end
