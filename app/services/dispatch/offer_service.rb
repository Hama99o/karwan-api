module Dispatch
  # Offers a job to the next courier.
  #
  # Crude on purpose, per CLAUDE.md: nearest eligible courier, a deadline, then
  # the next one, then a human. No batching, no optimisation, no zones.
  #
  # THE COURIER GETS ONE OFFER AT A TIME, never a list. A list needs reading and
  # comparing, and invites cherry-picking that starves the far jobs — so
  # dispatch picks and the courier answers yes or no.
  #
  # Returns the Offer, or nil when there is nobody left to ask. Nil is not a
  # failure: it is the signal that the job needs a human, which is the case the
  # brief says to build FIRST because it is what keeps the business operable
  # while the automation is wrong.
  class OfferService
    def initialize(job)
      @job = job
    end

    def call
      return nil if @job.terminal?
      return nil if exhausted?
      return nil if pending_offer?

      courier = next_courier
      return nil if courier.nil?

      @job.offers.create!(
        courier: courier,
        sequence: next_sequence,
        status: :offered,
        offered_at: Time.current,
        expires_at: Setting.fetch("dispatch_offer_ttl_sec").seconds.from_now
      )
    end

    # Why this job could not be offered, for the admin board. Distinguishing
    # "we have asked five people" from "nobody is on shift" is the difference
    # between waiting and phoning someone.
    def blocked_reason
      return :terminal if @job.terminal?
      return :offers_exhausted if exhausted?
      return :awaiting_response if pending_offer?
      return :no_eligible_courier if next_courier.nil?

      nil
    end

    private

    def exhausted?
      @job.offers.count >= Setting.fetch("dispatch_max_offers")
    end

    # Never two live offers for one job — that is how two couriers both turn up
    # at the merchant and one has wasted a trip.
    def pending_offer?
      @job.offers.pending.exists?
    end

    def next_sequence
      (@job.offers.maximum(:sequence) || 0) + 1
    end

    # Nearest first, among couriers who are eligible and have not already been
    # asked. Distance is straight-line — v0 has no router, and for choosing
    # between couriers in one neighbourhood the ordering is the same either way.
    def next_courier
      return @next_courier if defined?(@next_courier)

      @next_courier = candidates.min_by { |candidate| candidate[:distance] }&.fetch(:courier)
    end

    def candidates
      already_asked = @job.offers.pluck(:courier_id)
      pickup = @job.pickup_coordinates
      return [] if pickup.nil?

      CourierProfile.dispatchable_for(@job.class.job_kind)
                    .where.not(user_id: already_asked)
                    .includes(user: :courier_wallet)
                    .filter_map do |profile|
        next unless Dispatch::Eligibility.new(courier: profile.user, job: @job).eligible?

        distance = Geo::Distance.km(
          from_lat: profile.last_latitude, from_lng: profile.last_longitude,
          to_lat: pickup[0], to_lng: pickup[1]
        )
        next if distance.nil?

        { courier: profile.user, distance: distance }
      end
    end
  end
end
