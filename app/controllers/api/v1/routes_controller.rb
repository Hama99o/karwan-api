# THE DRAWN LINE BETWEEN TWO PINS, BY ROAD.
#
# ── Why this did not exist ────────────────────────────────────────────────
#
# Every other side of this was already built and the seam between them was
# missed, which is why the map still drew a dashed straight line:
#
#   * `Routing::OsrmClient` asks for `overview=full&geometries=geojson` and
#     returns the geometry untouched;
#   * `Customers::QuoteSerializer:74` already emits it as `route_geometry`, so
#     the CART path has carried road geometry end to end for weeks;
#   * the app's `RouteMap` already draws a LineString, solid for a real route
#     and dashed with the "نږدې اندازه" notice for the fallback.
#
# What was missing was a door. The app fetched `${MAP_URL}/route/v1/driving/…`
# — the MAP host, where there is no router — while `config/deploy.yml:179` runs
# OSRM as an API accessory on `127.0.0.1:5000`. Two correct decisions taken
# weeks apart in different repos, pointing at different hosts. The app asked,
# got a 404, and fell back honestly. That is why it looked abandoned.
#
# ── Not role-namespaced, deliberately ────────────────────────────────────
#
# Same reasoning as `me`: one map screen is shared by customer, courier and
# merchant, and "how do I get from here to there" means the same thing to all
# three. A role namespace here would be three identical controllers.
class Api::V1::RoutesController < Api::V1::BaseController
  # A PROXY THAT TAKES ARBITRARY COORDINATES, which nothing else in this API
  # does — `/table` only ever saw merchant pins we already held. Authentication
  # alone does not bound it: one signed-in account can ask for a thousand
  # cross-country routes, and OSRM's CPU is Hamma9900's VPS. Correction 6 makes
  # the per-order marginal cost the binding constraint, so the limit is part of
  # the endpoint rather than an afterthought.
  #
  # By USER, not by IP. Afghan mobile networks put many subscribers behind one
  # NAT address, so an IP limit here would throttle a neighbourhood to punish
  # one account.
  throttle to: 60, within: 1.minute, by: :user

  def show
    # No record to authorize — the same shape as `couriers/jobs#show` and
    # `merchant_applications`, both of which call this for the same reason.
    skip_authorization

    return render_outside_service_area unless both_pins_in_country?

    route = Routing::DistanceResolver.new(
      from_lat: params.require(:from_latitude), from_lng: params.require(:from_longitude),
      to_lat: params.require(:to_latitude), to_lng: params.require(:to_longitude)
    ).call

    return render_unprocessable_entity("we could not measure that route", code: "unroutable") if route.nil?

    render_ok({ route: payload(route) })
  end

  private

  def payload(route)
    {
      distance_km: route.distance_km,
      duration_minutes: route.duration_minutes,
      # A Karwan concept OSRM has no field for. The fallback has to be
      # expressible in the same shape, or the app needs two response formats.
      source: route.source,
      # GEOJSON, UNTOUCHED, and **nil on the fallback rather than a synthesised
      # two-point line**. `RouteMap` already falls back to [start, end] itself;
      # a server-built two-point "geometry" would arrive looking like a road and
      # nothing downstream could tell the difference. Same value and same shape
      # as `route_geometry` on the quote path, so the app parses one thing.
      geometry: route.geometry,
      pin_far_from_road: route.pin_far_from_road?
    }
  end

  def both_pins_in_country?
    Geo::Bounds.contains?(lat: params[:from_latitude], lng: params[:from_longitude]) &&
      Geo::Bounds.contains?(lat: params[:to_latitude], lng: params[:to_longitude])
  end

  # The router's graph is the Afghanistan extract. A pin outside it is a
  # question we cannot answer, and saying so is better than a snapped road
  # several hundred kilometres from where the user pointed.
  def render_outside_service_area
    render_unprocessable_entity("that location is outside the area we cover",
                                code: "outside_service_area")
  end
end
