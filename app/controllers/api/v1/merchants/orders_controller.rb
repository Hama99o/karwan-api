# The order board: the merchant's default and only real screen.
class Api::V1::Merchants::OrdersController < Api::V1::Merchants::BaseController
  before_action :set_order, only: %i[show accept reject preparing ready]

  # Live orders by default, oldest first — the opposite of the customer's list.
  # A kitchen works the queue from the front; showing newest first would bury
  # the order that has been waiting longest.
  def index
    orders = merchant_orders.includes(order_items: :selected_options)
    orders = params[:status].present? ? orders.where(status: params[:status]) : orders.live
    orders = orders.order(:created_at)

    paginate_blue(Merchants::OrderSerializer, orders, extra: { view: :board })
  end

  def show
    authorize @order, :show?

    render_blue(Merchants::OrderSerializer, @order, view: :detailed)
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

    reason = params[:reason].to_s
    unless Order.rejection_reasons.key?(reason)
      return render_unprocessable_entity(
        "reason must be one of: #{Order.rejection_reasons.keys.join(', ')}",
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

    # Accepting is what makes an order dispatchable, so dispatch starts here
    # rather than on a timer. Offering inline keeps the courier's phone ringing
    # while the kitchen is still putting the lid on.
    Dispatch::OfferService.new(@order).call if to_status == :accepted

    render_blue(Merchants::OrderSerializer, @order.reload, view: :detailed)
  end
end
