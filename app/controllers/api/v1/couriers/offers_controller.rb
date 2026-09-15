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

    ApplicationRecord.transaction do
      @offer.respond!(:accepted)
      # Assignment and the transition together: a job with a courier but no
      # accepted transition, or the reverse, is a state nobody can explain.
      job.update!(courier: current_user)
      job.transition_to!(next_status_for(job), actor: current_user, actor_role: :courier)
      # Everyone else's offer on this job is now moot. Left `offered`, the
      # expiry job would re-offer work that is already taken.
      job.offers.status_offered.where.not(id: @offer.id).update_all(status: :superseded)
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

  # A delivery is accepted straight to `picked_up`? No — the courier accepting
  # a delivery does not yet have the food. `accepted` already happened when the
  # merchant took it, so a delivery needs no transition here; a ride does.
  def next_status_for(job)
    job.is_a?(Order) ? :preparing : :accepted
  end
end
