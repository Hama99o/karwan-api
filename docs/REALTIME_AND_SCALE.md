# Live tracking, dispatch and scale — the plan, with numbers

Hamma9900's question, and it is the right one to be worried about:

> "it can be very, very big problem if we have a thousand users which need a
> live application, a live system for them. So make sure you have a vision
> about that."

This document answers it with arithmetic rather than opinion, because the
honest answer turns out to be cheaper and simpler than the instinctive one.

**The headline: v0 does NOT need WebSockets.** At 1,000 concurrent live jobs the
whole live system is about 210 requests/second of single-row indexed reads,
which one VPS handles at roughly a tenth of its capacity. WebSockets are the
right answer later, and the trigger for switching is written down below rather
than left to instinct.

---

## 1. The two things people call "live", which have opposite requirements

Conflating these is the mistake that makes live systems expensive.

| | **State changes** | **Position** |
|---|---|---|
| Examples | order accepted, ready, picked up, delivered | where the courier is right now |
| How often | ~6 times per order, over ~40 minutes | every few seconds, for ~20 minutes |
| Matters when app is closed? | **Yes** — a missed "new order" is a lost order | No — nobody watches a map in their pocket |
| Latency tolerance | seconds | seconds |
| Right mechanism | **push (FCM)** | **poll while the screen is open** |

**State changes are pushed, not polled.** They are rare, they must arrive when
the app is closed, and FCM is free. This is already the brief's rule for the
merchant alert — "never rely on a single delivery mechanism" — so it is push,
plus in-app polling while open, plus an SMS/phone path.

**Position is polled, not pushed.** It only matters while somebody is looking at
a map, it is worthless a minute later, and it does not need to survive the app
being closed.

---

## 2. Why polling, not WebSockets, for v0

### The load, computed

Assume the pessimistic case Hamma9900 asked about: **1,000 concurrent live jobs**
— which at ~13 jobs per courier per day is a city far larger than one Kabul
neighbourhood.

| Source | Rate | Requests/sec |
|---|---|---|
| Customers watching a courier, polling every 10s | 1,000 clients | **100** |
| Couriers reporting position every 10s | 1,000 couriers | **100** |
| Merchant order boards, polling every 5s | 50 merchants | **10** |
| **Total** | | **~210 req/s** |

Every one of those is a single indexed row read or a single-row update.
Measured on this box against 20,000 seeded orders, that class of query runs in
**3–13ms**. Puma with 2 workers × 5 threads sustains roughly 1,000–2,000 req/s
of such work, so 210 req/s is **10–20% utilisation**. There is no problem here.

### Why WebSockets would be *worse*, not better, at this stage

1. **1,000 persistent connections cost real memory** — roughly 1GB before the
   app does anything, on a VPS Hamma9900 is paying for himself.
2. **`solid_cable` broadcasts by polling Postgres** (default every 0.1s). At
   scale that is its own constant load, and we chose Postgres-for-everything
   deliberately to avoid a Redis bill.
3. **Afghan connectivity breaks persistent connections.** A dropped WebSocket
   reconnects, re-authenticates and re-subscribes. On a flaky 3G link that
   handshake happens repeatedly and costs *more* data and battery than a plain
   GET every 10 seconds. `docs/AFGHAN_UX.md` is explicit that data costs the
   user money.
4. **Polling degrades gracefully; WebSockets fail cliff-edged.** A failed poll
   shows last-known position with a quiet "not updated" marker — exactly the
   offline state DESIGN.md requires. A dead socket shows nothing until it
   recovers.

### What the user actually pays, in data

A position response is ~200 bytes of JSON, ~500 bytes with headers. A 20-minute
delivery polled every 10s is 120 requests ≈ **60 KB per order**. That is
negligible, and it is bounded — polling stops when the screen closes and when
the job reaches a terminal state.

### When to switch, stated in advance so it is a measurement and not a mood

Move position updates to ActionCable when **any** of these is true:

- p95 latency on the tracking endpoint exceeds **200ms**
- sustained request rate exceeds **40%** of measured capacity
- more than ~**5,000** concurrent live jobs
- the position write rate makes `courier_profiles` a contention point

`solid_cable` is already configured, so the switch is a channel and a client
change, not a re-architecture. **Do not do it before the numbers say so.**

---

## 3. The write side, which is the part that actually bites

Reads scale trivially. The risk is 100 position **writes** per second onto a row
that carries five indexes.

Current shape: `courier_profiles.last_latitude / last_longitude /
location_updated_at`, one row per courier, updated in place.

- `record_location!` writes **three columns and no indexed one**, so Postgres
  does not touch an index on the hot path.
- **A stale fix is not a location.** `location_fresh?` refuses anything older
  than 5 minutes — dispatch must never offer work based on where somebody was an
  hour ago.
- History is deliberately not kept. One row per courier means the table stays
  small and hot in cache forever, rather than growing by 8.6M rows a day.

**If writes become the bottleneck**, in order of preference:
1. Have the courier app batch — one write every 15s instead of every 5s.
2. Write position to `solid_cache` (Postgres, already present) and flush to the
   row periodically. Position is disposable; losing the last 15 seconds of it on
   a crash costs nothing.
3. Only then consider a separate append-only table or Redis.

---

## 4. What is NOT built, and what has to be decided

### Who may read a courier's position — **the important one**

Only the customer and the merchant of that courier's **currently active job**,
and only while it is active. Never the fleet, never after delivery.

This is an authorization rule and it is exactly the mistake `edu-safi` made five
times over: the correct scope existed, was correct, and **was never consulted**.
So: write the scope *and* use it, with a request spec proving **both** the
refusal and the legitimate path. A policy spec alone passes on all five of those
endpoints.

### Position at the moments that get disputed — recommended

Where the courier was when they marked **picked up** and **delivered**. Two
columns per job, written once. It is the only evidence that exists when a
customer says the food never arrived, and it cannot be reconstructed later.

### Breadcrumbs — v1, and they have a purpose

A position history per job, for **calibrating the ETA speed setting from real
deliveries**, which `CLAUDE.md` already asks for. Needs a retention policy
before it is built, or it becomes the largest table in the database.

---

## 5. The map — self-hosted, zero marginal cost

Hamma9900: *"the map system is the most important"*. It is also the place where a
per-order fee would otherwise appear, so it is self-hosted end to end.

| Need | How | Cost per order |
|---|---|---|
| Tiles | `hatiwal-map`: planetiler → pmtiles → nginx → kamal-proxy | **0** |
| GPS position | the phone's own OS via `expo-location` | **0** |
| Geocoding | self-hosted Nominatim, `countrycodes=af` | **0** |
| Routing (later) | self-hosted OSRM, same `.pbf` extract | **0** |
| Distance / ETA (v0) | straight line ÷ `eta_average_speed_kmh` setting | **0** |

**GPS is not a map provider.** The phone gives lat/lng for free; there is
nothing to integrate and nothing to meter.

Three traps already documented and not to be rediscovered:

1. **`bounds` in `build-styles.mjs` must match planetiler's `--bounds` exactly**,
   or MapLibre requests tiles that do not exist.
2. **A routing service becomes a THIRD consumer of the same extract.** Build
   OSRM from the same `.pbf`, or it will route over roads the map does not draw.
3. **Offline tiles are a v0 requirement here**, unlike in Hatiwal. A courier in
   a stairwell still has to see where they are going. Turn on MapLibre's ambient
   cache and pre-download the working city at z10–z15. Hatiwal has an open
   blank-band bug from tiles failing on weak networks and never being retried —
   do not inherit it.

Per correction 12: **extend `hatiwal-map`, keep it backwards compatible, add
OSRM alongside rather than in place of anything.** Hatiwal launches first and
must not be destabilised.

---

## 6. Dispatch, and why it is deliberately crude

1. Job becomes assignable (merchant accepts a delivery; a ride is requested)
2. Offer to the nearest available courier who **accepts that job kind** and
   whose **wallet can fund it**
3. Countdown (`dispatch_offer_ttl_sec`, default 60) → no answer, offer the next
4. After `dispatch_max_offers` → **surface to admin to assign by hand**
5. Admin can always reassign

No batching, no optimisation, no zones. **Build the manual override first** — it
is what makes the business operable while the automation is wrong.

**The courier gets ONE offer at a time, never a list.** A list needs reading and
comparing, and invites cherry-picking that starves the far jobs. Dispatch picks;
the courier accepts or declines.

**The wallet gate differs by job kind, and this is not an accident:**

| | Wallet must cover |
|---|---|
| Delivery | the **advance** — `merchant_payout` — which the courier fronts at the counter |
| Ride | nothing; only that the wallet is not blocked |

So a courier too short for a delivery can still earn on a ride. Refusing them
both would take income from the side of the market whose supply is already
scarce.

**Two jobs that do not exist yet and must before launch:**
- a recurring job that expires timed-out offers and moves to the next courier
- a recurring job that acts on `Order::TIMEOUTS` / `Trip::TIMEOUTS`

Until those exist, a job can sit in its first state forever. `docs/NOTES.md`
carries this as an open gap.

---

## 7. Build order, and where each layer's tests live

Per `docs/ARCHITECTURE.md`, controllers are namespaced **by role**, never one
controller with `if current_user.courier?`. Duplication between roles is cheaper
than coupling between roles, because roles diverge and the conditionals never
get removed.

```
app/controllers/api/v1/customer/    merchant/    courier/    admin/
app/serializers/customer/           merchant/    courier/
app/policies/
app/services/
```

| Step | What | Test that must exist |
|---|---|---|
| 1 ✅ | Migrations, models, factories | model spec: every public method, every scope |
| 2 | Policies, per role | policy spec **and** a request spec proving refusal AND the legitimate path |
| 3 | Serializers, **one per role** | request spec asserting the exact keys |
| 4 | Services — pricing, dispatch, transitions, wallet | service spec including the failure branch and rollback |
| 5 | Controllers, namespaced per role | rswag request spec: happy path, auth failure, validation failure |
| 6 | Jobs — offer expiry, state timeouts, push | job spec asserting the effect, not that it ran |

**A serializer per role, not one with conditionals.** The same order is three
different things: the courier sees the pickup address and the cash to collect,
the customer sees an ETA and a first name, the merchant sees neither.

**The courier's active job is ONE screen for both kinds.** The serializer sends
an ordered **step list** — each step a location, an action, and optionally an
amount. A delivery serialises four steps, a ride three. That keeps `if food` out
of the mobile code, and a third demand type costs a step list rather than a new
screen. This is the pattern Grab, Gojek and Yandex Go all use.

---

## 8. Earnings and reporting

What Hamma9900 asked to be able to see: **how much we earned, how much each
merchant earned, how many customers we have**, and per-partner statements.

Everything needed is already stored, and none of it needs a new table to start:

| Question | Source |
|---|---|
| Platform revenue | `sum(commission)` over delivered orders and completed rides, **grouped by currency** |
| One merchant's sales | `items_total` over their delivered orders |
| What a merchant received in cash | `merchant_payout`, paid at every pickup — under Model A we never owe them |
| A courier's earnings | `courier_fee` on deliveries + `courier_earnings` on rides |
| What a courier owes us | their wallet balance — already the answer, by design |
| Cash not yet settled | `Order.unsettled` / `Trip.unsettled`, an indexed column not a join |
| Courier utilisation — **the number the business turns on** | jobs per courier per day, both kinds, one pool |

**Never sum across currencies.** Group by it. v0 is AFN-only, which is exactly
when that is cheap to get right.

**Recommendation: snapshot a statement when it is issued**, rather than
recomputing it. A statement is a financial record shown to a partner, and a
later change to the calculation would silently rewrite what somebody was shown
last month. Same argument as `order_items`; `settlements` already works this way.

---

## 9. Payments — NOT built; the schema simply does not block one

Cash only in v0. But the schema already accommodates a provider with **no
migration**:

- `payment_status` is payment-method-**neutral** — `pending → collected →
  settled` for cash, `pending → paid → settled` for digital
- `payment_method` is an integer enum, so a value is added in Ruby alone
- wallet balances and ledger amounts are **signed and bidirectional**, because
  online payment **inverts** the relationship: today the courier holds the cash
  and owes us commission; with a provider we hold the money and owe the courier
  their fee

That inversion is the non-obvious part, and it is why there is deliberately no
non-negative constraint on either balance or amount — with live money in the
table, removing one is a migration.

No `payments` table and no provider abstraction until a provider is chosen:
modelling one that does not exist yet guesses wrong about refunds, webhooks and
settlement timing.
