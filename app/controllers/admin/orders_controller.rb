# The live order board, and every intervention on an order.
#
# The interventions are the point. A default Administrate install gives you a
# CRUD form; what makes a delivery business operable is being able to reassign a
# courier, cancel an order, or mark one failed — **each one logged with who did
# it**, which a generic form edit could never record.
module Admin
  class OrdersController < Admin::ApplicationController
    # Live first, oldest first: the board is a work queue, and the order that
    # has waited longest is the one somebody needs to look at.
    # Live first, oldest first: the board is a work queue, and the order that
    # has waited longest is the one somebody needs to look at. Terminal orders
    # sort to the bottom rather than being hidden, because "what happened to
    # that one" is asked as often as "what needs doing".
    def scoped_resource
      base = Order.includes(:merchant, :customer, :courier)
      filtered(base).order(
        Arel.sql(
          "CASE WHEN status IN (#{Order::STATUSES.values_at(*Order::TERMINAL).join(',')}) " \
          "THEN 1 ELSE 0 END, created_at ASC"
        )
      )
    end

    private

    # The board's own buttons, rather than Administrate's search box — an
    # operator during a rush wants one click, not a query.
    def filtered(scope)
      case params[:filter]
      when "overdue" then scope.live.overdue
      when "unassigned" then scope.live.where(courier_id: nil)
      when "unsettled" then scope.unsettled
      else scope
      end
    end

    public

    # Hand the order straight to a named courier, skipping dispatch. This is
    # the manual override CLAUDE.md says to build FIRST — it is what keeps the
    # business operable while the automation is wrong.
    def reassign
      order = requested_resource
      courier = User.find(params.require(:courier_id))
      before = order.courier_id

      order.update!(courier: courier)
      # Any live offer is now moot; left alone the expiry sweep would re-offer
      # work an operator has just assigned by hand.
      order.offers.status_offered.update_all(status: :superseded)

      log_intervention("order.reassigned", target: order,
                                           before: { courier_id: before },
                                           after: { courier_id: courier.id },
                                           details: { by_hand: true })
      redirect_back fallback_location: admin_order_path(order), notice: "Reassigned to #{courier.display_name}."
    end

    def cancel
      order = requested_resource
      moved = order.transition_to!(:cancelled, actor: nil, actor_role: :admin,
                                               reason: params[:reason].presence || "cancelled by operator")

      if moved
        order.update(cancellation_reason: :other, cancelled_by_role: :admin)
        log_intervention("order.cancelled", target: order, after: { status: "cancelled" },
                                            details: { reason: params[:reason] })
        redirect_back fallback_location: admin_order_path(order), notice: "Order cancelled."
      else
        redirect_back fallback_location: admin_order_path(order),
                      alert: "An order that is #{order.status} cannot be cancelled."
      end
    end

    # Failing an order is a money decision — the platform absorbs the food cost
    # and reimburses the courier the same day — so the reason is mandatory and
    # comes from the fixed list, keeping "failure reasons ranked" countable.
    def fail
      order = requested_resource
      reason = params[:reason].to_s

      unless Order.failure_reasons.key?(reason)
        return redirect_back fallback_location: admin_order_path(order),
                             alert: "Pick a reason: #{Order.failure_reasons.keys.join(', ')}."
      end

      moved = order.transition_to!(:failed, actor: nil, actor_role: :admin, reason: reason)
      if moved
        order.update!(failure_reason: reason)
        log_intervention("order.failed", target: order, after: { status: "failed", failure_reason: reason })
        redirect_back fallback_location: admin_order_path(order), notice: "Order marked failed."
      else
        redirect_back fallback_location: admin_order_path(order),
                      alert: "An order that is #{order.status} cannot be failed."
      end
    end

    # Re-runs dispatch by hand for an order nobody took.
    def redispatch
      order = requested_resource
      offer = Dispatch::OfferService.new(order).call

      log_intervention("order.redispatched", target: order,
                                             details: { offered_to: offer&.courier_id,
                                                        blocked: Dispatch::OfferService.new(order).blocked_reason })
      notice = offer.present? ? "Offered to #{offer.courier.display_name}." : "No eligible courier right now."
      redirect_back fallback_location: admin_order_path(order), notice: notice
    end
  end
end
