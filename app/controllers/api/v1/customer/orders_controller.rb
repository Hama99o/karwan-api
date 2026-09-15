# The customer's own orders: price one, place one, watch it, cancel it.
class Api::V1::Customer::OrdersController < Api::V1::BaseController
  before_action :set_order, only: %i[show cancel]

  def index
    orders = policy_scope(Order).includes(:merchant, :order_items).newest_first

    paginate_blue(Customer::OrderSerializer, orders, extra: { view: :list })
  end

  def show
    authorize @order, :show?

    render_blue(Customer::OrderSerializer, @order, view: :detailed)
  end

  # Prices a cart WITHOUT creating anything.
  #
  # Correction 4: money is shown before it is owed. This exists so the customer
  # sees the total before committing, and it deliberately calls the same
  # `Pricing::DeliveryQuote` the order will use — a second formula for the
  # preview is how the quoted price and the charged price drift apart.
  def quote
    authorize Order, :create?

    merchant = Merchant.kept.status_active.find(order_params[:merchant_id])
    result = Orders::QuoteService.new(
      merchant: merchant, lines: cart_lines,
      delivery_latitude: order_params[:delivery_latitude],
      delivery_longitude: order_params[:delivery_longitude]
    ).call

    render_blue(Customer::QuoteSerializer, result)
  rescue Orders::PlaceService::Error, Pricing::DeliveryQuote::Error => e
    render_unprocessable_entity(e.message, code: error_code_for(e))
  end

  def create
    authorize Order, :create?

    merchant = Merchant.kept.status_active.find(order_params[:merchant_id])
    order = Orders::PlaceService.new(
      customer: current_user, merchant: merchant, lines: cart_lines,
      delivery_latitude: order_params[:delivery_latitude],
      delivery_longitude: order_params[:delivery_longitude],
      delivery_landmark_note: order_params[:delivery_landmark_note],
      customer_phone: order_params[:customer_phone],
      notes: order_params[:notes]
    ).call

    render_blue(Customer::OrderSerializer, order, view: :detailed, status: :created)
  rescue Orders::PlaceService::Error, Pricing::DeliveryQuote::Error => e
    render_unprocessable_entity(e.message, code: error_code_for(e))
  end

  def cancel
    authorize @order, :cancel?

    moved = @order.transition_to!(:cancelled, actor: current_user, actor_role: :customer,
                                              reason: params[:reason])
    return render_unprocessable_entity("this order can no longer be cancelled", code: "not_cancellable") unless moved

    @order.update(cancellation_reason: :customer_changed_mind, cancelled_by_role: :customer)
    AuditLog.record!(action: "order.cancelled", actor: current_user, actor_role: :customer,
                     target: @order, after: { status: "cancelled" })

    render_blue(Customer::OrderSerializer, @order, view: :detailed)
  end

  private

  def set_order
    @order = policy_scope(Order).find(params[:id])
  end

  def order_params
    params.require(:order).permit(
      :merchant_id, :delivery_latitude, :delivery_longitude,
      :delivery_landmark_note, :customer_phone, :notes
    )
  end

  # Line items come as an array; nothing in them is an amount. The client sends
  # WHAT was chosen, never what it costs — a client that can name its own price
  # is a client that will.
  def cart_lines
    raw = params.require(:order)[:lines]

    # Defensive about the shape, not just the values. A form-encoded empty
    # array arrives as `[""]` — one blank STRING, not an empty list — so the
    # obvious `.map { |line| line.permit(...) }` raises NoMethodError and the
    # customer gets a 500 for sending an empty cart. Anything that is not a
    # parameter hash is dropped, and an empty result is reported as an empty
    # cart, which is what it is.
    lines = Array(raw).filter_map do |line|
      next unless line.respond_to?(:permit)

      permitted = line.permit(:catalog_item_id, :quantity, :notes, option_value_ids: [])
      {
        catalog_item_id: permitted[:catalog_item_id],
        quantity: permitted[:quantity],
        notes: permitted[:notes],
        option_value_ids: Array(permitted[:option_value_ids])
      }
    end

    raise Orders::PlaceService::EmptyCart, "an order needs at least one item" if lines.empty?

    lines
  end

  # A stable marker per failure, so a client with three locales renders its own
  # message instead of showing an English sentence from the server.
  def error_code_for(error)
    case error
    when Orders::PlaceService::MerchantUnavailable then "merchant_unavailable"
    when Orders::PlaceService::ItemUnavailable then "item_unavailable"
    when Orders::PlaceService::InvalidOptions then "invalid_options"
    when Orders::PlaceService::EmptyCart then "empty_cart"
    else "cannot_price_order"
    end
  end
end
