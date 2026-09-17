# The courier's current offer.
#
# ONE AT A TIME, NEVER A LIST — and `show` returns a single object rather than a
# collection so the API itself cannot be used to build a list screen. A list
# needs reading and comparing, and invites cherry-picking that starves the far
# jobs. Dispatch picks; the courier answers yes or no.
class Api::V1::Couriers::OffersController < Api::V1::Couriers::BaseController
  before_action :set_offer, only: %i[accept decline]

  def show
    offer = current_offer

    # Nothing to authorise when there is no offer — see jobs#show.
    if offer.nil?
      skip_authorization
      return render_ok({ offer: nil })
    end

    authorize offer, :show?

    render json: {
      offer: {
        id: offer.id,
        sequence: offer.sequence,
        job: Couriers::JobSerializer.render_as_hash(
          offer.offerable, view: :offer,
          offer: offer, from: courier_profile.coordinates
        )
      }
    }
  end

  def accept
    authorize @offer, :accept?

    # Re-checked at the moment of acceptance, not only when offered. Between
    # the offer and the tap the wallet may have been charged for another job, or
    # the merchant may have closed — and the courier would be committed to work
    # they cannot fund.
    eligibility = Dispatch::Eligibility.new(courier: current_user, job: @offer.offerable)
    unless eligibility.eligible?
      return render_unprocessable_entity(eligibility.explanation, code: eligibility.reason.to_s)
    end

    if @offer.expired?
      @offer.respond!(:timed_out)
      return render_unprocessable_entity("this offer has expired", code: "offer_expired")
    end

    job = @offer.offerable

    # LOCKED ON THE COURIER, and re-checked inside the lock.
    #
    # `Eligibility` above runs before the transaction, so two taps arriving
    # together — two phones, or one phone and a retry on a bad connection —
    # could both pass it and both assign. The lock serialises accepts for THIS
    # courier, and the re-check is what the second one then fails on.
    #
    # Locking the courier rather than the job is deliberate: the constraint
    # being protected is "one human, one vehicle, one place at a time", which
    # is a fact about the courier. Two couriers accepting two different jobs
    # must not block each other.
    conflict = nil
    ApplicationRecord.transaction do
      current_user.lock!
      conflict = Dispatch::Eligibility.new(courier: current_user, job: job).reason
      raise ActiveRecord::Rollback if conflict

      @offer.respond!(:accepted)
      job.update!(courier: current_user)

      # THE DEAD LEG IS PRICED HERE because this is the first moment it exists:
      # the leg is courier→merchant and at quote time there was no courier.
      # Frozen onto the row like every other amount (correction 13). It changes
      # nothing the customer was quoted — it moves money from our commission to
      # the courier — so no customer-facing figure moves.
      #
      # A SET, not this one job: batched, two jobs share one ride out, and paid
      # per job we would fund a leg nobody rode twice (correction 19). One job
      # today.
      #
      # AFTER `job.update!(courier:)` AND NOT BEFORE, which is load-bearing
      # rather than incidental: assigning the courier is what sets
      # `courier_fee` from HIS vehicle's rate — the second freeze point in
      # docs/TESTING.md's frozen-amounts spec, because the vehicle is unknown
      # until somebody accepts. Computed above that line, the top-up would
      # measure the shortfall against a fee the courier is not being paid, and
      # would be wrong in whichever direction his vehicle differs from the
      # placeholder. An example asserts the ordering.
      topups = Pricing::CourierTopUp.for(courier: current_user, jobs: [ job ])
      job.update!(commission_topup: topups[job]) if topups[job]

      # ACCEPTING A DELIVERY CHANGES NO ORDER STATUS, and this was wrong at
      # first: it moved the order to `preparing`, which conflated "a courier
      # took the job" with "the kitchen started cooking". Those are different
      # facts owned by different people. The merchant owns
      # placed -> accepted -> preparing -> ready; the courier's first real
      # action is paying at the counter, which is what moves it to `picked_up`.
      #
      # A ride has no merchant, so there the courier's acceptance IS the
      # transition.
      job.transition_to!(:accepted, actor: current_user, actor_role: :courier) if job.is_a?(Trip)

      # Everyone else's offer on this job is now moot. Left `offered`, the
      # expiry sweep would re-offer work that is already taken.
      job.offers.status_offered.where.not(id: @offer.id).update_all(status: :superseded)
    end

    if conflict
      return render_unprocessable_entity(
        Dispatch::Eligibility::REASONS[conflict], code: conflict.to_s
      )
    end

    render_blue(Couriers::JobSerializer, job.reload, view: :active)
  end

  # No reason required. Asking a courier to justify a decline, one-handed, in
  # traffic, is how declines become timeouts — and a timeout costs the customer
  # the whole TTL instead of nothing.
  def decline
    authorize @offer, :decline?

    @offer.respond!(:declined)
    # Straight to the next courier rather than waiting for the sweep.
    Dispatch::OfferService.new(@offer.offerable).call

    head :no_content
  end

  private

  def current_offer
    Offer.pending.where(courier_id: current_user.id).includes(:offerable).chronological.first
  end

  def set_offer
    @offer = Offer.where(courier_id: current_user.id).find(params[:id])
  end
end
