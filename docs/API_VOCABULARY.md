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

**Money shapes:** every amount is a JSON **string** (`"500.0"`, `"-50.0"`),
never a number, and each is paired with a `currency`. A client comparing them
numerically without parsing gets the wrong answer for negatives — which is the
short-settlement case exactly. See `spec/fixtures/files/courier_wallet_settlements.json`
for a captured example.

## C · NEVER MET — the F-74 shape waiting to happen

**This is the valuable half of the list.** These exist on the server and have
never crossed the wire, so no client word exists yet and nothing can be
"agreeing by coincidence". The first caller decides the vocabulary, and if it
invents its own there is nothing to catch it.

| vocabulary | values | status |
|---|---|---|
| **order cancellation reason** | `customer_changed_mind` `merchant_unavailable` `no_courier_available` `duplicate` `other` | **Not serialized anywhere.** `customers/orders#cancel` HARD-CODES `customer_changed_mind` and puts `params[:reason]` into the transition's free text instead. So five values exist and a customer can express exactly one. |
| **trip cancellation reason** | `passenger_changed_mind` `courier_unavailable` `no_courier_available` `duplicate` `other` | same — not on the wire |
| **payment status** | `pending` `collected` `settled` | not in any mobile serializer. Drives the cash-in-hand gate that stops dispatch offering work, and no app can see it |
| **theme** | `system` `light` `dark` | stored on `User`, **not serialized**. A settings screen would invent its own |
| **courier job kinds** | `delivery` `ride` | `CourierProfile::JOB_KINDS`; used as a ROUTE SEGMENT (`/jobs/:kind/...`), not as a payload field |
| **merchant status** | `pending` `active` `suspended` `rejected` `lead` | ops-console vocabulary; a customer sees `accepting_orders`, not this |
| **offer status** | `offered` `accepted` `declined` `timed_out` `superseded` | internal to dispatch |

**Before writing a client for any row in C, ask for the word.** That is the
question nobody asked about `roles`.
