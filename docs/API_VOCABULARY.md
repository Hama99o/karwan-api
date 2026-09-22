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
| **dispatch** | `offer_expired` `not_your_job` `cannot_advance` `wrong_step` `too_early_to_arrive` `wallet_blocked` |
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

`ErrorCodes.reachable_in_normal_use` returns the **53** that are not OTP,
malformed requests or server state. The ten it excludes are `otp_*` (switched
off), `bad_request`, `bad_platform`, `not_found`, `registration_invalid` and
`pending_migration`.

> **This number said 25 for an hour**, written when the vocabulary was 35 and
> not revisited when twenty-five dynamic codes were folded in. It is the count
> the mobile session sizes its translation work from, so a stale one is not a
> cosmetic error. It is now asserted in `spec/config/api_vocabulary_spec.rb`,
> which is what caught it.
