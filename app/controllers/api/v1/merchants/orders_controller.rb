# The order board: the merchant's default and only real screen.
class Api::V1::Merchants::OrdersController < Api::V1::Merchants::BaseController
  before_action :set_order, only: %i[show acknowledge accept reject preparing ready]

  # Live orders by default, oldest first — the opposite of the customer's list.
  # A kitchen works the queue from the front; showing newest first would bury
  # the order that has been waiting longest.
  def index
    # `transitions` because every card now answers WHY it ended, and that reads
    # the transition log to tell the shop's own refusal from a timeout. Without
    # the preload it is a query per order on the board's busiest screen.
    orders = merchant_orders.includes(:transitions, order_items: :selected_options)
    orders = params[:status].present? ? orders.where(status: params[:status]) : orders.live
    orders = orders.order(:created_at)

    # ── "NOTHING CHANGED" COSTS TWO QUERIES, NOT THIRTEEN ─────────────────
    #
    # The board polls every 10 s per open shop, and almost every poll finds
    # the same board. `fresh_when` answers 304 BEFORE the thirteen queries
    # run; `Rack::ETag` would only have hashed the finished body, saving bytes
    # and none of the work.
    #
    # THE KEY CARRIES A MINUTE. `minutes_in_state` and `is_overdue` are
    # computed from the clock, so a key on the orders alone would answer 304
    # while "waiting 3 min" froze and an order went overdue unseen. The minute
    # bucket matches the granularity the card already has (`minutes_in_state`
    # is floored to whole minutes); the overdue flag, and a courier's name or
    # phone (read from `users`, not the order), can be up to 59 s late —
    # Hamma9901's decision, 24 Sept 2026. At most one full recompute per shop
    # per minute, instead of six.
    freshness = [ current_merchant&.id, params[:status], params[:page], params[:per_page],
                  orders.unscope(:includes, :order).count, orders.unscope(:includes, :order).maximum(:updated_at)&.to_f,
                  Time.current.to_i / 60 ]
    return unless stale?(etag: freshness, public: false)

    paginate_blue(Merchants::OrderSerializer, orders, extra: { view: :board })
  end

  def show
    authorize @order, :show?

    render_blue(Merchants::OrderSerializer, @order, view: :detailed)
  end

  # ── A HUMAN HAS SEEN IT ───────────────────────────────────────────────────
  #
  # Not a state transition: the order is still `placed` afterwards and nothing
  # about it has been decided. It answers the one question the server could not
  # answer before — whether the alert was HEARD, as opposed to delivered.
  #
  # The console already counts pushes that reached no device. This is the other
  # half and the worse one, because it looks fine: the push arrived, on a tablet
  # on a counter in a noisy kitchen, and nobody looked at it.
  #
  # IDEMPOTENT, and it must be. The alarm screen retries on a bad connection,
  # so the second call answers 200 with the FIRST acknowledgement's time rather
  # than moving it — "when did somebody first see this" stops being answerable
  # the moment a retry can overwrite it.
  def acknowledge
    authorize @order, :acknowledge?

    @order.acknowledge_by_merchant!(current_user)

    render_blue(Merchants::OrderSerializer, @order.reload, view: :detailed)
  end

  def accept
    transition!(:accepted)
  end

  # A reject must carry a reason from a fixed list. Free text would mean nobody
  # can count why orders are refused, and "failure reasons ranked" is a report
  # the owner asked for.
  def reject
    # AUTHORIZE FIRST, then validate. Two reasons, and the first is the
    # important one: telling someone their reason is invalid, before checking
    # whether they may reject this order at all, leaks validation feedback to
    # somebody with no business here.
    #
    # The second is mechanical — `verify_authorized` raised
    # Pundit::AuthorizationNotPerformedError on the early return, turning a 422
    # into a 500. That guard catching my own ordering mistake is exactly what it
    # is for.
    authorize @order, :rejected?

    # `MERCHANT_REJECTION_REASONS`, NOT the whole enum. The column also carries
    # `no_answer`, which the timeout job writes about a shop that never replied —
    # and a shop that CAN send it could label its own refusal as "we were never
    # asked", which is the one line on the report that decides whether the owner
    # rings a restaurant or replaces a tablet.
    reason = params[:reason].to_s
    unless Order::MERCHANT_REJECTION_REASONS.include?(reason)
      return render_unprocessable_entity(
        "reason must be one of: #{Order::MERCHANT_REJECTION_REASONS.join(', ')}",
        code: "reason_required"
      )
    end

    transition!(:rejected, already_authorized: true) { @order.update!(rejection_reason: reason) }
  end

  # "We have started cooking." The step the board had no button for.
  def preparing
    transition!(:preparing)
  end

  def ready
    transition!(:ready)
  end

  private

  # Explicitly the MERCHANT scope. `policy_scope(Order)` would resolve to the
  # customer's own orders and return an empty board — which is exactly what it
  # did before this was fixed.
  def merchant_orders
    policy_scope(Order, policy_scope_class: OrderPolicy::MerchantScope)
  end

  def set_order
    @order = merchant_orders.find(params[:id])
  end

  # One path for every board action, so each is a real state transition with an
  # actor and a timestamp rather than a status being overwritten. Correction:
  # five buttons, five explicit transitions.
  def transition!(to_status, already_authorized: false)
    authorize @order, :"#{to_status}?" unless already_authorized

    moved = @order.transition_to!(to_status, actor: current_user, actor_role: :merchant_owner)
    unless moved
      return render_unprocessable_entity(
        "an order that is #{@order.status} cannot become #{to_status}",
        code: "invalid_transition"
      )
    end

    yield if block_given?

    # ANY ACTION ON THE BOARD IS PROOF SOMEBODY SAW IT. The new-order alarm
    # calls `acknowledge`, but a cook may tap Accept (or Reject) straight from
    # it, and before this an order moved that way kept `merchant_acknowledged_at`
    # empty forever — "when did a human first see it" had no answer for the
    # very orders somebody acted on fastest. First acknowledgement still wins:
    # an order already acknowledged keeps its earlier time.
    @order.acknowledge_by_merchant!(current_user)

    # Accepting is what makes an order dispatchable, so dispatch starts here
    # rather than on a timer. Offering inline keeps the courier's phone ringing
    # while the kitchen is still putting the lid on.
    Dispatch::OfferService.new(@order).call if to_status == :accepted

    render_blue(Merchants::OrderSerializer, @order.reload, view: :detailed)
  end
end
