# Every enumeration this API sends or accepts, and who owns the word

Written for the mobile repo to diff its own declarations against, after two
types called `Role` were found with **no translation anywhere** — the server's
`merchant_owner` against the app's `merchant` — and the only reason nothing had
broken was that nothing had ever read the field. The first honest caller would
have hidden merchant mode from every restaurant owner while passing every test
written from the same assumption.

**This half is the server's vocabulary only.** Which words the client
re-declares, and which agree by coincidence, is the other half and belongs to
whoever can read that repo. Kept current by `spec/config/api_vocabulary_spec.rb`.

## Who owns the word

**The server owns it; the client translates at its own boundary.** Not
preference — these words are in database columns and in `audit_logs` /
`status_transitions` rows, which `CLAUDE.md` names a one-way door. Renaming a
server word is a migration over historical rows that must stay readable;
renaming a UI token is a rename. **The side that can change cheaply is the side
that translates.**

So `merchant_owner` stays `merchant_owner` on the wire, and a UI vocabulary
with `merchant` in it maps at the edge, in one place, not at each call site.

---

## A · The server sends the VOCABULARY, not just a value

The best shape, because the client cannot disagree — it renders what it is
given, and no copy exists to drift.

| what | where | note |
|---|---|---|
| `problem_reasons` | `couriers/job_serializer.rb` (`:active`) | sends the LIST itself, and `couriers/jobs_controller#problem` validates against the same source. One definition, both directions. |

For a delivery the list is `customer_refused` `nobody_home`
`customer_unreachable` `wrong_address` `other`; for a ride
`passenger_no_show` `passenger_unreachable` `passenger_refused` `unsafe`
`other`.

**Both also carry `fake_note`** (24 Sept 2026, `TRUST_AND_REPUTATION.md` §4) —
the customer's only money was a counterfeit the courier refused. It is
**held back from `problem_reasons`** until the `fake_note_reason_offered`
Setting is on, because the app would otherwise show the raw key: switch it on
in the same release that adds the label (`Dispatchable.offered_failure_reasons`
is the one source for the sheet and the endpoint).

**The values are written here even though the client never declares them**,
because sending the vocabulary removes the *branching* problem and not the
*translation* one: each reason still needs a Pashto string, and a screen
rendering a raw `customer_unreachable` to a courier in Kabul has failed
differently. The list above is what needs translating; the server will not
send a word that is not on it.

**Copy this shape for anything new.** It is the only category here that cannot
produce an F-74.

## B · On the wire as VALUES the client must recognise

Each of these arrives as a bare string the client has to branch on, so each is
a place a re-declaration can silently disagree.

| vocabulary | values | carried by |
|---|---|---|
| **roles** | `customer` `courier` `merchant_owner` `admin` | `shared/user_serializer.rb` (`roles`), accepted by `me#switch_role`, `auth/registrations`, `auth/sessions` |
| **mobile roles** | `customer` `courier` `merchant_owner` | `Roles::MOBILE` — `ALL` minus `admin`. **There is no role called `merchant`.** |
| **order status** | `placed` `accepted` `preparing` `ready` `picked_up` `delivered` `rejected` `cancelled` `failed` | customer order/track, merchant order, courier job |
| **trip status** | `requested` `accepted` `arrived` `in_progress` `completed` `cancelled` `failed` | courier job |
| **service tier** | `normal` `premium` | `couriers/job_serializer.rb`; accepted by `customers/orders#quote` and `#create`. `premium` is refused while `premium_tier_enabled` is off, with code `tier_unavailable` |
| **distance source** | `osrm` `straight_line` | `customers/quote_serializer.rb` (`distance_source`), `customers/merchant_serializer.rb`, and on a courier's offer `couriers/job_serializer.rb` (`distance_source` for `distance_km`, which is always `straight_line`, and `onward_distance_source` for `onward_distance_km`). `osrm` means **by road**. On the offer the two distances are different kinds of number: to the shop is a straight line from his last fix, and the onward leg is the road his fee was priced on. They must not be shown as though they were alike |
| **`located_seconds_ago`** (a number, not a vocabulary, listed here because two clients must read it the same way) | integer seconds, or **null** | `customers/track_serializer.rb` (`courier.located_seconds_ago`) and the courier's offer (`couriers/job_serializer.rb`, how old the fix behind `distance_km` is). Measured by the SERVER's clock, the same one `STALE_AFTER` uses, so a phone never subtracts `located_at` from its own. **Null means never seen**, which is a different sentence from a large number. Sent even when the position itself is withheld as stale |
| **vehicle type** | `motorbike` `bicycle` `car` `on_foot` `rishka` `zarang` | `couriers/registration_serializer.rb`; accepted by `couriers/registrations` |
| **wallet entry kind** | `commission` `top_up` `reimbursement` `adjustment` `commission_topup` | `couriers/wallet_entry_serializer.rb` |
| **currency** | `AFN` | every money-bearing payload. `Monetary::SUPPORTED_CURRENCIES` is a one-element list **today** — it is a field on every amount by a one-way-door decision, so treat it as a real dimension, not a constant to hard-code |
| **locale** | `ps` `fa` `en` | `shared/user_serializer.rb`, and accepted nearly everywhere as a parameter |
| **order rejection reason** | `out_of_stock` `too_busy` `closing` `other` `no_answer` | `customers/order_serializer.rb` (`ended_reason.code`). **The column's vocabulary, which is wider than the board's** |
| **what the BOARD may send** | `out_of_stock` `too_busy` `closing` `other` | `Order::MERCHANT_REJECTION_REASONS`, enforced by `merchants/orders#reject`. `no_answer` is written only by `Dispatch::JobTimeoutsJob`, about a shop that never replied — a merchant sending it would label its own refusal "we were never asked". **A merchant-side picker must offer these four, not the five above.** |
| **order cancellation reason** | `customer_changed_mind` `merchant_unavailable` `no_courier_available` `duplicate` `other` | `customers/order_serializer.rb` (`ended_reason.code`). Read-only: `customers/orders#cancel` still hard-codes `customer_changed_mind` — see C |
| **who ended it** | `customer` `courier` `merchant_owner` `admin` `system` — or **null** | `ended_reason.ended_by`. `system` means a nil actor did it (the timeout job); **null means no transition was recorded**, which is not the same fact and must not be rendered as "the system" |

| **theme** | `system` `light` `dark` | `shared/user_serializer.rb` (`preferred_theme`), and ACCEPTED by `me#update`. Both directions |
| **courier job kinds** | `delivery` `ride` | `couriers/registration_serializer.rb` and `couriers/shifts#show` as `accepted_job_kinds`; `couriers/job_serializer.rb` and `wallet_entry_serializer.rb` as `job_kind`. Also a route segment, which is what hid it |
| **merchant status** | `pending` `active` `suspended` `rejected` `lead` | `merchants/profile_serializer.rb` and `shared/merchant_application_serializer.rb`. A CUSTOMER never sees it — they get `accepting_orders` — but the shop sees its own, and an applicant sees `lead` |
| **courier application status** | `pending` `approved` `rejected` `suspended` `needs_more` | `couriers/registration_serializer.rb` (`verification_status`). The applicant's screen branches on it: `needs_more` means "we asked you for something" and is the one a courier can act on. Pinned 24 Sept 2026, found read by the app and in neither this document nor the gate |
| **menu option kind** | `single` `multiple` | `customers/catalog_serializer.rb` and `merchants/catalog_serializer.rb` (`selection_type`). Decides whether a menu's choices render as one-of or any-of, so a new value is a menu that cannot be ordered from. Pinned 24 Sept 2026, same finding |
| **device platform, as an INPUT** | `android` `ios` | accepted by `me#device_token` and the sign-in and registration calls (`platform`; blank means `android`). Stored on `device_tokens` to route a push |
| **why a courier's phone is quiet** | nine of the fifteen eligibility reasons, or **null** | `couriers/shifts#show` (`blocked_by`) |

**`blocked_by` REUSES THE ELIGIBILITY VOCABULARY IN A SECOND CONTEXT, and that
is the thing to notice.** Those fourteen words are published in category D as
ERROR CODES — they arrive on a 422 when a courier taps accept. Eight of them now
also arrive as a **field value on a 200**, on the shift screen, describing the
courier rather than a refused action. A client that translates them only inside
its error handler will render nothing on the screen that needs them most.

The nine: `account_suspended` `no_profile` `not_approved` `off_shift`
`already_on_a_job` `stale_location` `no_wallet` `wallet_blocked` `cash_in_hand`.

The other six — `wrong_job_kind` `vehicle_too_small` `wrong_vehicle_class`
`too_many_passengers` `too_far` `insufficient_credit` — are about a PAIRING and
can never appear here, because a shift screen has no job to pair with.

**NULL IS A NEGATIVE CLAIM.** It means nothing about this courier is blocking
him. It does **not** mean work is coming: the six pairing reasons are still
live, and the commonest reason of all is that nobody has ordered anything. Do
not render it as "you will receive jobs".

**`ended_reason` is an object or null**, never a bare string:

```json
{ "outcome": "rejected", "code": "out_of_stock", "ended_by": "merchant_owner" }
```

Null on a live order and on a delivered one — there is nothing to explain about
an order that arrived. `code` is `unknown` when the column was never filled.
`outcome` is one of `rejected` `cancelled` `failed`, and it tells the client
WHICH vocabulary `code` is drawn from; the three lists do not overlap by
accident and must not be merged into one lookup.

**`ended_by` has FOUR possible speakers, and `admin` is one of them.**
`customer`, `courier`, `merchant_owner` — and **`admin`, which means a person at
Karwan decided it from the ops console.** That one is not a machine and must not
be rendered as one: it is the case where there is somebody to ring, and the
support number is in the app for exactly this. It used to come out as `system`,
because a console operator is an `AdminUser` and `status_transitions.actor_id`
references `users`, so the console had nowhere to record itself.

**Two nulls that are different facts, and the fixture shows them three rows
apart.** `ended_by: "system"` means a machine closed it — the timeout job, a nil
actor. `ended_by: null` means **nothing recorded who**, which
`db/seeds/stress.rb` produces in bulk. Rendering the second as "cancelled by
Karwan" tells a customer something the data does not support. And
`ended_reason: null` — the whole object absent — is a third fact again: the
order has not ended badly. A client testing only `ended_reason?.ended_by`
cannot tell a delivered order from an unattributed rejection.

**Money shapes:** every amount is a JSON **string** (`"500.0"`, `"-50.0"`),
never a number, and each is paired with a `currency`. **That includes advice
ABOUT an amount:** `bring_change_for` on a courier step and `suggested_notes` on
the customer's order and quote are amounts and are strings. They came from
`Monetary.change_advice`, which returned an **Integer** — `.ceil` on a BigDecimal
does — so all three served a bare `500` beside an `amount` of `"445.0"` until the
courier-job fixture was captured with a 160 AFN fare. Every earlier example had
a round hundred and got `nil`. A client comparing them
numerically without parsing gets the wrong answer for negatives — which is the
short-settlement case exactly. See `spec/fixtures/files/courier_wallet_settlements.json`
for a captured example.

**Per-currency figures are an ARRAY of objects carrying their own `currency`**,
never a map keyed by currency. One payload, one parser. The single exception is
`cash_allowance_remaining`, a scalar because `cash_in_hand_limit` is an
AFN-denominated `Setting` and the comparison is AFN-only by design — an array
there would imply a per-currency limit that does not exist.

**CAPTURED PAYLOADS, committed so a client can build against a fact rather than
a description.** Each has a contract spec that fails the moment the API stops
producing it, and the failure names the fixture to regenerate:

| endpoint | fixture |
|---|---|
| `couriers/wallet#settlements` | `spec/fixtures/files/courier_wallet_settlements.json` |
| `merchants/today#show` | `spec/fixtures/files/merchant_today.json` |
| `couriers/today#show` | `spec/fixtures/files/courier_today.json` |
| `customers/orders#index` — every `ended_reason` state at once | `spec/fixtures/files/customer_orders_ended_reason.json` |
| `couriers/jobs#show` — a delivery, four steps | `spec/fixtures/files/courier_job_delivery.json` |
| `couriers/jobs#show` — a ride, three steps | `spec/fixtures/files/courier_job_ride.json` |
| `public/merchants#catalog` — every orderability state | `spec/fixtures/files/public_catalog_orderability.json` |

`from`/`to` in both `today` payloads are **Kabul** boundaries (`+04:30`). A
client comparing them against a UTC day is off by four and a half hours and
attributes the dinner rush to the wrong date.

## C · NEVER MET — the F-74 shape waiting to happen

**This is the valuable half of the list.** These exist on the server and have
never crossed the wire, so no client word exists yet and nothing can be
"agreeing by coincidence". The first caller decides the vocabulary, and if it
invents its own there is nothing to catch it.

| vocabulary | values | status |
|---|---|---|
| **order cancellation reason, as an INPUT** | `customer_changed_mind` `merchant_unavailable` `no_courier_available` `duplicate` `other` | It is now READ on the wire (category B), but still cannot be SENT: `customers/orders#cancel` HARD-CODES `customer_changed_mind` and puts `params[:reason]` into the transition's free text. Five values exist and a customer can express exactly one. Whether a customer may claim `merchant_unavailable` is Hamma9900's. |
| **trip cancellation reason** | `passenger_changed_mind` `courier_unavailable` `no_courier_available` `duplicate` `other` | same — not on the wire |
| **payment status** | `pending` `collected` `settled` | not in any mobile serializer. Drives the cash-in-hand gate that stops dispatch offering work, and no app can see it |
| **offer status** | `offered` `accepted` `declined` `timed_out` `superseded` | internal to dispatch |

**Before writing a client for any row in C, ask for the word.** That is the
question nobody asked about `roles`.

### THREE ROWS OF THIS SECTION WERE WRONG, AND IT IS THE SECTION THAT IS TRUSTED

`theme`, `courier job kinds` and `merchant status` were all listed here as never
having crossed the wire, and all three were in serializers — `preferred_theme`
is serialized AND accepted as input, `accepted_job_kinds` and `job_kind` appear
in four payloads, and a merchant sees its own `status` on its profile.

**This is the most damaging place in the document to be stale.** Section C's
purpose is to tell a mobile session where no server word exists yet, so a wrong
entry sends somebody to invent a vocabulary that is already on the wire — which
is precisely the `Role` mismatch this file was written after.

`spec/config/api_vocabulary_spec.rb` now checks the claim mechanically for every
vocabulary whose attribute name is distinctive enough to search for, and names
the ones it cannot check. The list of values was always asserted; what rotted
was the prose about WHERE they appear, and prose is what a reader acts on.

---

## D · ERROR CODES — the vocabulary that had no owner

`code:` is what lets a client say something in Pashto; the `error` string is for
a developer reading a log. **61 codes are declared in `ErrorCodes`**
(`app/models/concerns/error_codes.rb`), which exists because until now they had
no declaration at all — every controller wrote its own inline, so the list could
only be recovered with a grep, and it drifted to 35 while the app named 7.

`spec/models/error_codes_spec.rb` holds it in both directions: nothing emitted
may be undeclared, nothing declared may be unemitted.

| group | codes |
|---|---|
| **auth** | `unauthorized` `forbidden` `invalid_credentials` `account_unavailable` `already_registered` `registration_invalid` `role_not_held` `phone_required` |
| **otp** — unreachable, correction 2 | `otp_disabled` `otp_expired` `otp_invalid` `otp_not_issued` `otp_throttled` |
| **reset** | `reset_code_invalid` `reset_invalid` `reset_throttled` |
| **ordering** | `no_merchant` `merchant_is_a_lead` `tier_unavailable` `not_cancellable` `invalid_transition` `reason_required` |
| **dispatch** | `offer_expired` `not_your_job` `cannot_advance` `wrong_step` `too_early_to_arrive` `wallet_blocked` `job_taken` |
| **courier access** | `no_courier_profile` | 403 from any `/courier/*` route for an account with no courier profile. **Declared 24 Sept 2026 — it had gone out for weeks undeclared**, as a positional argument the `code:` scan could not see. The same fact Eligibility calls `no_profile`: two words for one thing, kept until the app can move with a rename |
| **merchant self-service** | `invalid_opening_hours` |
| **geography** | `outside_service_area` `unroutable` |
| **infrastructure** | `bad_request` `not_found` `bad_platform` `rate_limited` `pending_migration` |
| **account deletion** — `me#destroy`, 422 | `holding_cash` `wallet_unsettled` `live_job` `live_order` `merchant_orders_in_flight` |
| **re-authentication** | `reauthentication_required` — switching a live session INTO `courier` or `merchant_owner` needs the password again. `IDENTITY_AND_ROLES.md` §7 and correction 18: the sign-in choice is the gate for entering a role, and a switch inside a session had never passed it. **Switching back to `customer` needs nothing** — the gate is on reaching the money, not on leaving it. A missing password and a wrong one give the IDENTICAL answer. |
| **eligibility** — why a courier may not take this job | `account_suspended` `no_profile` `not_approved` `off_shift` `wrong_job_kind` `vehicle_too_small` `too_many_passengers` `wrong_vehicle_class` `already_on_a_job` `stale_location` `too_far` `no_wallet` `wallet_blocked` `insufficient_credit` `cash_in_hand` |

### The half a grep could not see

The first version of this section said 35, and that number was produced by an
instrument that could only read `code: "a_literal"`. **Twenty-five more reach
clients from expressions** — `code: deletion.reason.to_s`,
`code: error_code_for(e)`, `code: eligibility.reason.to_s`, `code: refusal.to_s`
— including the fourteen eligibility reasons a courier meets in an ordinary
week, and the five fixable refusals on account deletion.

`spec/models/error_codes_spec.rb` now requires **every `code:` that is not a
literal to be accounted for by name**, so the next dynamic one fails until
somebody says where its words come from. Also added:
`not_a_mobile_role`, and the six from `error_code_for` — `item_unavailable`,
`invalid_options`, `empty_cart`, `no_vehicle_for_this_order`,
`cannot_price_order`, `merchant_unavailable`.

**`merchant_unavailable` is a word in two different vocabularies** — an error
code here, and a value of `Order.cancellation_reasons` in category C. They are
unrelated and must not be mapped to one string on a client.

**`outside_service_area` and `unroutable` are different answers and must not be
collapsed.** The first says we do not cover that place; the second says we cover
it and could not find a way. A client treating them alike draws an approximate
line to somewhere we have said we do not go — a wrong answer, not a missing one.
Asserted by its own example.

**The three an ordinary person meets doing an ordinary thing**, and so the three
most worth a real sentence: `offer_expired` (a courier taps Accept a second
after the countdown — the job went to somebody else and another will come),
`not_cancellable` (a customer cancels as the merchant accepts — the restaurant
has started cooking), and `outside_service_area`.

`ErrorCodes.reachable_in_normal_use` returns the **57** that are not OTP,
malformed requests or server state. The thirteen it excludes are `otp_*` (switched
off), `bad_request`, `bad_platform`, `not_found`, `registration_invalid`,
`pending_migration`, `invalid_idempotency_key` (a client bug, like
`bad_request`; its sibling `idempotency_key_reused` is a customer's real
situation and is counted), and `invalid_location`: a device fix that cannot be
a place, refused by `POST /courier/shift/location` and never shown to anybody,
because the app reports positions fire-and-forget and the next real fix
follows within seconds; and `invalid_expected_amount`, a client bug (its sibling
`price_changed` is the customer's real situation, and is counted).

> **This number said 25 for an hour**, written when the vocabulary was 35 and
> not revisited when twenty-five dynamic codes were folded in. It is the count
> the mobile session sizes its translation work from, so a stale one is not a
> cosmetic error. It is now asserted in `spec/config/api_vocabulary_spec.rb`,
> which is what caught it.

## E · PLACING AN ORDER AT MOST ONCE — the `Idempotency-Key` contract

**24 Sept 2026.** The phone blocks a double tap, but it cannot know whether a
`POST /customer/orders` whose answer never came back had landed, and a retry
placed a second order. This is the contract karwan-mobile builds against.
Server: `Api::V1::Customers::OrdersController#create`,
`Orders::RequestFingerprint`.

**Send:** header `Idempotency-Key`, 8–64 characters of `A–Z a–z 0–9 - _` (a
UUID fits). Optional: no header behaves exactly as before.

**When to make one:** when checkout OPENS, not when the button is pressed. A
key made per press gives every retry a fresh key and protects nothing. Keep it
across retries. Drop it after a success (a 201) or after a 409 (below). Make a
new one the next time checkout opens.

| Request | Status | Body | App does next |
|---|---|---|---|
| New key | **201** | `{ order: … }` | as today |
| Same key, same request | **201** | `{ order: … }`, same serializer and view, **the order as it now stands** | treat it exactly as a first success; it cannot tell the two apart and should not try |
| Same key, different request | **409** | `{ error, code: "idempotency_key_reused", order: … }`, with `order` the one that EXISTS | show him that order ("you already placed KQA…"). Placing the changed basket too is his choice, made under a **new key**: that is the one moment the protection is deliberately dropped, so it must be a deliberate act and never an automatic retry |
| Malformed key | **422** | `{ error, code: "invalid_idempotency_key" }` | a client bug; nothing was placed |

**What "the same request" means.** A SHA-256 over every field the client
SENDS that the server reads, and nothing the server computes:
`merchant_id`, `delivery_address_id` (as resolved to one of his own addresses),
`delivery_latitude`, `delivery_longitude`, `delivery_landmark_note`,
`customer_phone`, `notes`, `service_tier` (as resolved), and each line's
`catalog_item_id`, `quantity`, `notes`, `option_value_ids`.
- **No amount is in it**, because the client sends none. A menu price that
  changes between two attempts does not turn a real retry into a conflict: the
  existing order keeps the price it was placed at.
- **Canonical**, so a harmless difference is not a conflict:
  - blank and missing are the same;
  - coordinates are compared at the column's six decimal places;
  - integers are compared as integers (`"2"` equals `2`);
  - the lines are a basket, so their order does not matter;
  - neither does the order of a line's options.
- **Not merged:** one line with quantity 2 and two lines with quantity 1 are
  different requests.

**Scope and lifetime.**
- Keys are **per customer**. The same key from another customer places their
  own order, and never returns anyone else's.
- A key **never expires**: it is stored on the order it placed, so it
  identifies that order for good. A client that reuses a key days later gets
  that order back (201) or a 409. It never gets a silent second order.
- **A retry is answered even if the shop has closed since.** The key is looked
  up before the merchant is.

**Two attempts at the same moment** both find nothing under the key. A unique
index on (customer, key) lets one insert, and the other is answered as a
repeat: 201 with the same order, or 409 if its body differed.

**Error codes** `idempotency_key_reused` and `invalid_idempotency_key` are in
`ErrorCodes::ORDERING`.

## E2 · HE PAYS NO MORE THAN HE WAS SHOWN — `expected_amount_to_pay_in_cash`

**24 Sept 2026.** Placement re-prices from scratch. So a shop raising a price
between the quote and the tap placed the order at the new figure (518.56 shown,
768.56 placed, 201).

- **Send** `expected_amount_to_pay_in_cash` on `POST /customer/orders`: the
  `amount_to_pay_in_cash` the confirm screen showed. It's optional; without it
  the order places as before.
- **Higher now** → **409** `{ error, code: "price_changed", quote: … }`, with the
  quote in the same shape as `/orders/quote`, and **nothing placed**. Show him
  the new amount; when he confirms, send it again with the new figure.
- **Lower now** → **201** at the lower figure. The shown amount is kept on the
  order (`shown_amount_to_pay_in_cash`, console only), so the difference is
  visible.
- **Not a number** → 422 `invalid_expected_amount`.
- **With the `Idempotency-Key` (§E):** a 409 placed nothing, so the retry under
  the SAME key places normally. The expected amount isn't part of "the same
  request": it's what he agreed to pay, not what he ordered.

## F · PUSH NOTIFICATIONS — what the server sends, and what a phone would show

**24 Sept 2026.** The server sends KEYS, not words (`Notifications::FcmClient`):
the title and body arrive as `data.title_key` / `data.body_key`, and the app is
meant to localise them. Nothing on the phone handles a push yet, and there are no
Firebase credentials. Both of those are the owner's. This table is the server's
half, derived from the send sites and held to the code by
`spec/config/push_keys_are_published_spec.rb`.

| notification | fires when | `title_key` / `body_key` | data | deep link | alarm? |
|---|---|---|---|---|---|
| shop: new order | an order is placed (`Orders::PlaceService`) | `merchant.alert.new_order.title` `merchant.alert.new_order.body` | `order_id` `order_code` `item_count` `merchant_payout` `currency` | `karwan://open/new-order/:order_id` | **yes**, the only one; and the only one in words (below) |
| customer: courier at the gate | the courier taps "I am here" (`Couriers::AnnounceArrivalService`) | `customer.arrival.title` `customer.arrival.body`; for a RIDE, `customer.arrival.ride.title` `customer.arrival.ride.body` (the delivery copy says "with order … go to the door") | `kind` `job_id` `code` `courier_phone` | `karwan://open/arrival/:kind/:job_id` | no |
| courier: are you all right? | a job sits past its timeout (`Dispatch::JobTimeoutsJob`), once per stuck state | `courier.check_in.title` `courier.check_in.body` | `kind` `job_id` `code` `status` `support_phone` | `karwan://open/check-in/:kind/:job_id` | no |
| applicant: review outcome | an operator approves, rejects or asks for more (`CourierProfile`) | `courier.review.approved.title` `courier.review.approved.body` `courier.review.needs_more.title` `courier.review.needs_more.body` `courier.review.rejected.title` `courier.review.rejected.body` | `status` `missing` (JSON) `note` | `karwan://apply-rider` | no |

**Deep links say what happened and to which record, not which screen**
(`karwan://open/<event>/<record>`). The app's three role homes are route groups
that all sit at `/`, so a screen path from the server is ambiguous by
construction: the old `karwan://merchant/orders/:id` matched a customer's
restaurant page. The app decides the screen, so a layout change on its side
can't break this contract. `karwan://apply-rider` is unchanged.

**THE ONE DELIBERATE DUPLICATE: the shop's new-order alert, in words.** The
other pushes are data-only and worded by the app from its own i18n; a fully
closed app may show nothing for them, which their severity allows. The
new-order alert can't allow it, because a blank banner is a lost order. So the
server renders its `title` and `body` in the owner's saved `user.locale` and
sends a real `notification` block, which the OS draws with no handler.
- `*_loc_key` Android resources were ruled out: they resolve against the
  PHONE's system language, and Karwan's language is chosen in the app.
- The copy lives in `config/push/merchant_new_order.yml`, **mirrored from
  karwan-mobile, not authored there**, keeping the app's `{{name}}`
  placeholders.
- `spec/config/push_copy_mirrors_the_app_spec.rb` compares the two text for
  text in all three languages, and fails the day they differ. It skips, and
  says so, only where karwan-mobile isn't checked out beside the API.
- Change the words in the app first, then mirror them.

**What a phone would show today, if Firebase were switched on** (as first measured; the app has since written the twelve strings):
- **None of the 12 keys has a string in `karwan-mobile/src/i18n/locales/{en,ps,fa}.ts`.** Every notification would be wordless, in every language.
- **The OS draws nothing from these keys.** The only display block sent is
  `android.notification`, with a channel and a sound but no title, body or
  `*_loc_key`. So a closed app gets an empty banner, unless a handler builds the
  notification from `data`, or Android string resources exist under matching
  `*_loc_key` names. Which of those to build is the app's decision and the
  owner's (Firebase).
- **Two deep links matched no route** (`merchant/orders/:id`, `courier/job`).
  They were replaced by the `open/` links above.
- **Channels:** `karwan_orders` (the alarm) and `karwan_updates` (everything
  else) must be created by the app. On Android 8+ a channel that doesn't exist
  falls back to the system's default.
