# The ride door: the four customer endpoints, designed and NOT built (25 Sept 2026)

Nothing in `app/` creates a `Trip`. The only writers are `db/seeds/sample.rb`
and the stress seed's `insert_all`. `Pricing::RideQuote` exists with no
callers, and `/customer/*` has no trip routes. This is the design Hamma9901
asked for before anything is built. It is written against what already
exists, and it names the two decisions that are Hamma9900's.

## What already exists, and is kept

- **`Pricing::RideQuote`** (read in full): base + per-km + per-minute, a
  minimum, per-vehicle `PricingRate` rows, and a premium uplift that raises
  the fare AND the driver's share. Commission is by subtraction, so fare =
  commission + courier_earnings always. **The vehicle class is chosen BEFORE
  the price**, which is what lets a fare depend on the vehicle and still be
  frozen. A nil class means the any-vehicle rate.
- **`Trip`**: the state machine
  (`requested → accepted → arrived → in_progress → completed`), and a customer
  may cancel in `requested` AND `accepted`. The timeouts (`requested` 2 min),
  the frozen amounts, `passenger_count` validated against
  `VehicleTypes::MAX_SEATS`, `service_tier`, the snap distances, the route
  geometry and `distance_source`.
- **The food door's protections**, to mirror rather than reinvent:
  `Geo::Bounds` (`outside_service_area`), the pin warnings, the
  `Idempotency-Key` with a request fingerprint (API_VOCABULARY §E), and the
  shown amount beside the charged one (§E2).
- **Everything behind the door is proven**
  (`a_ride_through_the_shared_machinery_spec`): dispatch, the three courier
  steps, commission once, cash, settlement, the timeouts, and the console
  override (`526825e`).

## 1 · `POST /api/v1/customer/trips/quote`

**Sends:** `pickup_latitude`, `pickup_longitude`, `dropoff_latitude`,
`dropoff_longitude`, `passenger_count` (default 1), `service_tier`
(`normal` | `premium`, default normal), and optionally `vehicle_type`.

**Serves, one option per vehicle class that seats `passenger_count`**
(`CourierProfile.vehicle_types_seating`), so the passenger chooses between
cheap and comfortable with the prices in front of them, as RideQuote's own
comment argues:

```json
{ "quote": {
    "distance_km": "4.2", "distance_source": "osrm", "duration_minutes": 14,
    "pin_far_from_road": { "pickup": false, "dropoff": true },
    "options": [
      { "vehicle_type": "motorbike", "fare": "160.0", "currency": "AFN",
        "bring_change_for": "500.0", "change_due": "340.0",
        "fleet_available": true },
      { "vehicle_type": "car", "fare": "240.0", "currency": "AFN",
        "bring_change_for": "500.0", "change_due": "260.0",
        "fleet_available": false }
    ] } }
```

- `fleet_available` comes from `Dispatch::FleetCapability`, the same question
  as the delivery quote's `dispatch_warning`: nobody approved and on shift
  with that vehicle means "you can ask, but nobody may come". Said before the
  request, not discovered two minutes later as a cancellation.
- **Refusals** reuse the vocabulary: `outside_service_area` (either pin),
  `unroutable`, `too_many_passengers` (a count no class seats), and
  `tier_unavailable`.
- The customer sees the fare only. Commission and courier earnings are never
  served to a passenger.

## 2 · `POST /api/v1/customer/trips` (the request)

**Sends:** the quote's pins, `passenger_count`, `service_tier`, the chosen
`vehicle_type`, `pickup_landmark_note`, `dropoff_landmark_note`, the
**`expected_fare`** the screen showed, and an **`Idempotency-Key`** header.

**Does, in one request:**
1. Refuses exactly as the quote does.
2. Re-prices with a fresh `RideQuote` and applies **the fare rule (his; see
   below)**.
3. Creates the trip at `requested` with every amount frozen, the route
   geometry, the snaps and `distance_source`, plus the shown fare beside the
   charged one (the §E2 pattern, a `shown_fare` column).
4. **Calls `Dispatch::OfferService.new(trip).call` itself.** This is the
   ride-door item that would otherwise ship silently broken: without it,
   every request sits at `requested` until the timeout cancels it as
   `no_courier_available`. That's exactly the seed artefact that was
   mistaken for a supply problem tonight.

**Idempotency** gets its OWN fingerprint (`Trips::RequestFingerprint`), over
the pins rounded to ~1 m, `passenger_count`, `vehicle_type`, `service_tier`
and `expected_fare`. `Orders::RequestFingerprint` is order-shaped and can't
be reused. The answers are the ones §E already defines: a repeat with the
same fingerprint returns the same trip (200), and a reused key with a
different body gets 409 `idempotency_key_reused`.

**`passenger_phone`** defaults to the account's phone. Whether a customer may
book for someone else (the courier rings the person being picked up) is the
same question the food side answers yes to with `customer_phone`. It's
proposed as optional, normalised with `PhoneNumbers`.

**Serves** the trip, as the read below.

## 3 · `GET /api/v1/customer/trips/:id` (and `GET /customer/trips` for history)

`status`, `code`, the frozen `fare` and `currency`, `bring_change_for` and
`change_due`, the pins and landmark notes, `requested_at`, and
`cancellable` (a server-computed boolean, never inferred from status).
**Once accepted:** the courier's name, phone, vehicle type and plate. That's
the "asked for a car, waiting" state, then "Ahmad is coming, motorbike
KBL 4821". `TripPolicy#show?` already limits it to the passenger.

Live position is ride-door item 4, a separate `.../track` with the same
stale-fix withholding as `Customers::TrackSerializer`. It is NOT part of this
first slice.

## 4 · `POST /api/v1/customer/trips/:id/cancel`

- In `requested`: always, free. `cancellation_reason: passenger_changed_mind`,
  `cancelled_by_role: customer`, and the live offer is superseded, so a
  courier isn't left accepting a ride that is gone.
- In `accepted`: **the model already permits it**, but whether it costs the
  passenger anything (a courier has started driving) is in
  TRUST_AND_REPUTATION's OPEN cancellation cases. It's **his**. Until he
  rules, the endpoint answers `not_cancellable` after acceptance. That is the
  conservative reading, and it's reversible.
- Refusal: `not_cancellable`, the food door's code.

## Hamma9900's two decisions, which change what 1 and 2 carry

1. **The fare rule at request time.** (a) Honour the SHOWN fare exactly
   (correction 13's "quoted upfront and frozen"; the Afghan norm of agreeing
   the price before getting in), or (b) food's rule: refuse if the fresh fare
   is higher (409 `price_changed` with the new quote), and charge the lower
   one if it fell. Under (a) the quote needs a server-held token that expires,
   or the client could send any `expected_fare`. Under (b) it doesn't.
   **Proposed: (a) with a signed quote token valid for a few minutes**,
   because it's the only version where the number the passenger agreed to is
   the number the driver is paid on.
2. **Cancelling after acceptance:** free, a fee, or counted like the
   customer reliability signal. Until then, refused, as above.

## Order of building, once he answers

2 and 4 first: they are the door, and 2 must dispatch. Then 1, with its
options. Then 3. Tracking, then words for the ride pushes, come after, as
items 4 and 5 of the ride-door list in NOTES.
