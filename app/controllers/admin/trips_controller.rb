# The rides board, and every intervention on a ride.
#
# THE FIRST SLICE OF THE RIDE DOOR. Nothing can request a ride yet; this is
# built first because the brief says the manual override comes before the
# automation, and a ride that cannot be unstuck is a passenger standing in the
# street. Mirrors `Admin::OrdersController`'s four actions, with the two places
# a ride genuinely differs from a delivery:
#
#   * A courier's acceptance IS a ride's transition (`requested → accepted`;
#     see `couriers/offers#accept`). So assigning a requested ride by hand
#     moves it to `accepted` too — otherwise it would sit at `requested` with a
#     courier, and the requested timeout would cancel it as "no courier".
#   * Once the passenger is aboard (`in_progress`) the ride cannot be handed to
#     somebody else — the delivery's "after the shop is paid, this is not a
#     reassignment" (MONEY_AND_SETTLEMENT §8) in its ride form. It is failed, or
#     completed, by the courier who has the passenger.
#
# Unlike the order actions, each of these consults a policy (`TripPolicy`), so
# the route-derived sweep counts them as protected rather than adding four
# more rows to its list of actions that ask nothing.
module Admin
  class TripsController < Admin::ApplicationController
    def scoped_resource
      Trip.includes(:passenger, :courier).order(created_at: :desc)
    end

    def reassign
      trip = requested_resource
      authorize trip, :reassign?
      courier = User.find(params.require(:courier_id))
      before = trip.courier_id

      if trip.in_progress? || trip.terminal?
        return redirect_back fallback_location: admin_trip_path(trip),
                             alert: "This ride is #{trip.status.humanize.downcase}, so it cannot be handed to " \
                                    "another courier. #{trip.in_progress? ? 'The passenger is aboard; ring the courier, or mark it failed.' : ''}".strip
      end

      moved = true
      ApplicationRecord.transaction do
        trip.update!(courier: courier)
        # A courier's acceptance IS the ride's transition; a hand-assignment is
        # an acceptance made on his behalf.
        if trip.requested?
          moved = trip.transition_to!(:accepted, actor: nil, admin_user: current_admin_user,
                                                 actor_role: :admin, reason: "assigned by operator")
          raise ActiveRecord::Rollback unless moved
        end
        trip.offers.status_offered.update_all(status: :superseded, updated_at: Time.current)
      end

      unless moved
        return redirect_back fallback_location: admin_trip_path(trip),
                             alert: "That ride could not be assigned from #{trip.status}."
      end

      log_intervention("trip.reassigned", target: trip,
                                          before: { courier_id: before },
                                          after: { courier_id: courier.id, status: trip.status },
                                          details: { by_hand: true })
      redirect_back fallback_location: admin_trip_path(trip), notice: "Assigned to #{courier.display_name}."
    end

    def cancel
      trip = requested_resource
      authorize trip, :cancel?
      moved = trip.transition_to!(:cancelled, actor: nil, admin_user: current_admin_user, actor_role: :admin,
                                              reason: params[:reason].presence || "cancelled by operator")

      if moved
        trip.update(cancellation_reason: :other, cancelled_by_role: :admin)
        log_intervention("trip.cancelled", target: trip, after: { status: "cancelled" },
                                           details: { reason: params[:reason] })
        redirect_back fallback_location: admin_trip_path(trip), notice: "Ride cancelled."
      else
        redirect_back fallback_location: admin_trip_path(trip),
                      alert: "A ride that is #{trip.status.humanize.downcase} cannot be cancelled."
      end
    end

    # A reason from the fixed list, as for orders, so failures stay countable.
    def fail
      trip = requested_resource
      authorize trip, :fail?
      reason = params[:reason].to_s

      unless Trip.failure_reasons.key?(reason)
        return redirect_back fallback_location: admin_trip_path(trip),
                             alert: "Pick a reason: #{Trip.failure_reasons.keys.join(', ')}."
      end

      moved = trip.transition_to!(:failed, actor: nil, admin_user: current_admin_user, actor_role: :admin, reason: reason)
      if moved
        trip.update!(failure_reason: reason)
        log_intervention("trip.failed", target: trip, after: { status: "failed", failure_reason: reason })
        redirect_back fallback_location: admin_trip_path(trip), notice: "Ride marked failed."
      else
        redirect_back fallback_location: admin_trip_path(trip),
                      alert: "A ride that is #{trip.status.humanize.downcase} cannot be failed."
      end
    end

    # Re-runs dispatch by hand for a ride nobody took.
    def redispatch
      trip = requested_resource
      authorize trip, :redispatch?
      if trip.courier_id.present?
        return redirect_back fallback_location: admin_trip_path(trip),
                             alert: "This ride is already with #{trip.courier.display_name}. To move it, use reassign."
      end

      offer = Dispatch::OfferService.new(trip).call
      log_intervention("trip.redispatched", target: trip,
                                            details: { offered_to: offer&.courier_id,
                                                       blocked: Dispatch::OfferService.new(trip).blocked_reason })
      notice = offer.present? ? "Offered to #{offer.courier.display_name}." : "No eligible courier right now."
      redirect_back fallback_location: admin_trip_path(trip), notice: notice
    end
  end
end
