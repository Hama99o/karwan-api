# The customer's own orders: price one, place one, watch it, cancel it.
class Api::V1::Customers::OrdersController < Api::V1::BaseController
  # Far above real use — nobody orders forty meals a day — and it stops a loop
  # burying a merchant's board, which is the shape of abuse that costs a real
  # kitchen real time.
  throttle to: 40, within: 1.day, by: :user, only: :create
  # A quote is cheap but it calls the router, so it gets a looser ceiling.
  throttle to: 300, within: 1.hour, by: :user, only: :quote
  # Polled while a courier is moving — at one call every 10 seconds for a
  # 40-minute delivery that is 240, so the ceiling is high on purpose. It
  # exists to stop a client looping on a finished order, not to pace a normal
  # one.
  throttle to: 1_200, within: 1.hour, by: :user, only: :track

  before_action :set_order, only: %i[show cancel track]
  # REFUSED, NOT DOWNGRADED, and that is the opposite of what `tier_param` does
  # one screen below — so the difference is worth stating.
  #
  # `tier_param` turns an UNRECOGNISED tier into `normal` on purpose: a stale
  # client sending a word we retired must not fail an order, and the cheaper
  # tier is the safe landing. That reasoning does not carry here. `premium` is
  # recognised and switched OFF, and a silent downgrade would mean **nobody ever
  # finds out** — the client keeps asking, the screen keeps showing normal, and
  # the day §2 is answered and this flips, behaviour changes with no one having
  # known the gate was there. An explicit refusal is the only version anybody
  # can see.
  before_action :refuse_disabled_tier, only: %i[quote create]

  def index
    orders = policy_scope(Order).includes(:merchant, :order_items).newest_first

    paginate_blue(Customers::OrderSerializer, orders, extra: { view: :list })
  end

  def show
    authorize @order, :show?

    render_blue(Customers::OrderSerializer, @order, view: :detailed)
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
      delivery_longitude: order_params[:delivery_longitude],
      service_tier: tier_param
    ).call

    render_blue(Customers::QuoteSerializer, result)
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
      notes: order_params[:notes],
      service_tier: tier_param
    ).call

    render_blue(Customers::OrderSerializer, order, view: :detailed, status: :created)
  rescue Orders::PlaceService::Error, Pricing::DeliveryQuote::Error => e
    render_unprocessable_entity(e.message, code: error_code_for(e))
  end

  # Where the order is, for the map: the merchant's pin, their own pin, and the
  # courier's last fix while it is fresh.
  #
  # `OrderPolicy#track?` already existed and NOTHING CALLED IT — the exact
  # failure docs/NOTES.md records from edu-safi, "the correct scope existed,
  # was correct, and was never consulted". It refuses a terminal order, which
  # is why this is an endpoint rather than fields on the order: a customer
  # reading last week's delivered order would otherwise be able to watch that
  # courier for the rest of their shift.
  #
  # Throttled by USER rather than by IP. The app polls this while a courier
  # moves, so a generous ceiling is normal traffic — but a client left looping
  # on a dead order is someone spending Hamma9900's bandwidth, and CGNAT means
  # a whole neighbourhood can share one address.
  def track
    authorize @order, :track?

    render_blue(Customers::TrackSerializer, @order)
  end

  def cancel
    authorize @order, :cancel?

    moved = @order.transition_to!(:cancelled, actor: current_user, actor_role: :customer,
                                              reason: params[:reason])
    return render_unprocessable_entity("this order can no longer be cancelled", code: "not_cancellable") unless moved

    @order.update(cancellation_reason: :customer_changed_mind, cancelled_by_role: :customer)
    AuditLog.record!(action: "order.cancelled", actor: current_user, actor_role: :customer,
                     target: @order, after: { status: "cancelled" })

    render_blue(Customers::OrderSerializer, @order, view: :detailed)
  end

  private

  def set_order
    # `catalog_item` is preloaded because the serializer asks each line whether
    # its dish is still on the menu — without it that is a query per line on a
    # screen a customer opens while waiting for food.
    @order = policy_scope(Order)
             .includes(order_items: [ :catalog_item, :selected_options ])
             .find(params[:id])
  end

  def order_params
    params.require(:order).permit(
      :merchant_id, :delivery_latitude, :delivery_longitude,
      :delivery_landmark_note, :customer_phone, :notes, :service_tier
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

  # An unrecognised tier becomes `normal` rather than an error: the DEFAULT IS
  # THE CHEAPER, LESS-PROMISING ONE, so a stale client cannot accidentally sell
  # somebody a premium they did not ask for, and cannot fail an order over a
  # word. Charging more than a customer chose is the one mistake here that
  # costs trust.
  def tier_param
    tier = order_params[:service_tier].to_s
    ServiceTiers::ALL.key?(tier.to_sym) ? tier : "normal"
  end

  # Only a tier that is BOTH recognised and switched off is refused. An
  # unrecognised one falls through to `tier_param`'s downgrade, untouched.
  def refuse_disabled_tier
    tier = order_params[:service_tier].to_s
    return if tier.blank?
    return unless ServiceTiers::ALL.key?(tier.to_sym)
    return if ServiceTiers.orderable?(tier)

    render_unprocessable_entity(
      "the #{tier} tier is not available",
      code: "tier_unavailable"
    )
  end

  # A stable marker per failure, so a client with three locales renders its own
  # message instead of showing an English sentence from the server.
  def error_code_for(error)
    case error
    when Orders::PlaceService::MerchantUnavailable then "merchant_unavailable"
    when Orders::PlaceService::ItemUnavailable then "item_unavailable"
    when Orders::PlaceService::InvalidOptions then "invalid_options"
    when Orders::PlaceService::EmptyCart then "empty_cart"
    # Its own code, because the app must say something completely different:
    # not "try again" but "we cannot carry this — order something else". The
    # customer has done nothing wrong and retrying will never work.
    when Orders::PlaceService::NoVehicleForOrder then "no_vehicle_for_this_order"
    else "cannot_price_order"
    end
  end
end
