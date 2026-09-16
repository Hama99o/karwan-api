# Browsing, without a login.
#
# This is the first screen a user who was talked into installing the app will
# ever see, and correction 10 is explicit that they must reach it before being
# asked for anything. A login wall here is where they give up.
class Api::V1::Public::MerchantsController < Api::V1::PublicController
  # Browsing must never be the thing that locks somebody out — correction 10
  # is that a first-time user reaches a merchant before being asked for
  # anything. So this is set where only a script would reach it.
  throttle to: 600, within: 1.hour, by: :ip

  def index
    merchants = policy_scope(Merchant)
    merchants = merchants.search(params[:q]) if params[:q].present?
    merchants = merchants.by_merchant_category(params[:category_id]) if params[:category_id].present?
    # A closed merchant is shown greyed rather than hidden, so `open_now` is
    # opt-in rather than the default.
    merchants = merchants.where(is_open: true) if truthy?(params[:open_now])
    merchants = order_for(merchants)

    # ROAD DISTANCES FOR THE PAGE, in one request. `Geo::Distance.km` was
    # called per row here and in the serializer while the FARE went through
    # `DistanceResolver`, so the card said one distance and the fare was
    # computed from another — see `Routing::DistanceTable`.
    paginate_blue(
      Customers::MerchantSerializer, merchants,
      extra: { view: :list, locale: locale, from: origin },
      extra_for: ->(page) { { distances: road_distances(page) } }
    )
  end

  def show
    merchant = policy_scope(Merchant).find(params[:id])
    authorize merchant, :show?

    render_blue(Customers::MerchantSerializer, merchant, view: :detailed,
                                                        options: { locale: locale, from: origin })
  end

  # The merchant's own catalog, grouped as they group it.
  def catalog
    merchant = policy_scope(Merchant).find(params[:id])
    authorize merchant, :show?

    categories = merchant.catalog_categories.kept.ordered
                         .includes(catalog_items: [ :photo_attachment, { options: :values } ])

    render_blue_collection(Customers::CatalogSerializer, categories, options: { locale: locale })
  end

  private

  # ROAD DISTANCES FOR THE PAGE, in one request.
  #
  # Nil when there is no origin — a guest who has not shared a location gets a
  # list with no distances, which is the honest answer and is already rendered.
  def road_distances(page)
    return nil if origin.blank?

    Routing::DistanceTable.new(
      origin_lat: origin[0], origin_lng: origin[1],
      destinations: page.map { |m| { key: m.id, latitude: m.latitude, longitude: m.longitude } }
    ).call
  end

  # Nearest first when we know where the customer is, otherwise alphabetical.
  # Never a random order: a list that reshuffles between loads looks broken.
  def order_for(merchants)
    return merchants.alphabetical if origin.blank?

    # Ordered in SQL from the pins, rather than loading every merchant to sort
    # in Ruby — the same mistake the admin board's staleness scan made, and it
    # cost 287ms there.
    merchants.order(
      Arel.sql(
        ActiveRecord::Base.sanitize_sql_array(
          [ "((merchants.latitude - ?) * (merchants.latitude - ?)) + " \
            "((merchants.longitude - ?) * (merchants.longitude - ?)) ASC",
            origin[0], origin[0], origin[1], origin[1] ]
        )
      )
    )
  end

  # Squared degrees, not kilometres — it is only ever used to ORDER, and the
  # ordering is identical without the trigonometry or the square root. The
  # honest distance in the payload still comes from Geo::Distance.
  def origin
    return @origin if defined?(@origin)

    lat = params[:latitude]
    lng = params[:longitude]
    @origin = (lat.present? && lng.present?) ? [ lat.to_f, lng.to_f ] : nil
  end

  # The signed-in user's own locale wins; a guest sends one. Falls back to Dari.
  def locale
    current_user&.locale || params[:locale].presence_in(User::LOCALES) || "fa"
  end

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value) || false
  end
end
