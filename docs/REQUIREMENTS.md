# Requirements log — what Hamma9900 has actually asked for

Every requirement the owner has stated directly, dated, in his words plus what it
means for the code. **Nothing here is inferred.** When an item is built, it gets a
commit reference — not a tick, a reference, so the claim is checkable.

The point of this file is that requirements arrived as chat messages mid-task and
would otherwise live only in a session that will be summarised away.

---

## 2026-09-15

### R1 — Registration is not one flow. Riders and merchants are nothing like customers
> "remember regestration for resurant and rider is very defrent than cline
> client can be simple but not rider and resutrant"

**Customer:** phone + OTP + name. Nothing more. Every extra field is a customer lost.

**Rider:** identity (full name, father's name, tazkira number), vehicle type and
plate, a **guarantor** (name, phone, relation — the real trust mechanism in Kabul,
not a credit check), work area, documents, and an explicit **human approval** with
a name attached. A rider advances our merchants' food out of their own pocket
and carries our cash.

**Merchant:** the owner as a person separate from the business (name, phone,
tazkira), licence number, a **contact person who actually answers during a rush**
(often not the owner), documents, and the same explicit approval.

None of it can be collected later. An unverified rider who disappears with a
float is exactly the loss this data exists to prevent.

Built: `20260915120900_add_onboarding_to_riders_and_merchants` — schema.
Still open: document attachments, the approval endpoints, the admin screens.

### R2 — A good login system
> "and we should good login system"

Phone + OTP, and *good* means the parts people skip:
- OTP codes bcrypt-digested, looked up by phone, never stored in the clear
- Short TTL (5 min) and a **max attempt count** — 6 digits is 10^6 guesses, so
  the attempt counter is the actual protection, not the digest
- **Send throttling** per phone, so the endpoint is not an SMS bill or a way to
  harass a number — NOT YET BUILT, see docs/NOTES.md
- Session tokens 256-bit random, HMAC-SHA256 digested (deterministic, therefore
  indexable; bcrypt cannot be looked up by digest at all)
- Sessions listable and individually revocable; rotating `secret_key_base`
  invalidates every one
- A user with no password column at all, so there is nothing to phish or reuse

### R3 — The best search and category system for food
> "we should have best search system for food best category etc"

Two different things, and they were being conflated:
- `catalog_categories` is a **merchant's own menu structure** ("Starters", "Kebab",
  "Drinks"), entered by the merchant in its own language.
- **MerchantCategorys** are a **global, seeded taxonomy** ("Kabab", "Pizza", "Burger",
  "Afghan", "Fast food") used to browse and filter across merchants. This is
  what "best category" means and it did not exist in the first schema pass.

Search must hit **merchant names and dish names together** — people search
"mantu", which is a dish, not a merchant — be **multi-word** (each word narrows,
each word can match any field, per the house rule in hatiwal's backend prompt),
and be **typo- and transliteration-tolerant**, because "kabab / kebab / kabob"
are the same food and Pashto/Dari transliterations vary per person.

Built: `20260915121000_add_merchant_categories_and_search`.

### R4 — Administrate for the admin surface
> "make sure we have well system admistre gem can help to go admin part its
> important"

Settles an open question. `hatiwal-api` already runs Administrate **inside the API
repo** (`app/dashboards/`, `app/controllers/admin/`), which contradicted our brief's
separate `karwan-admin` repo. The owner's call is Administrate, and putting it
here is also the smaller v0: one repo, one deploy, no second frontend.

### R5 — Test everything, at every layer
> "rspect test evrething and unit test also and later we will do end to end and
> qa also note these thing"
> "we test each method each endpoint eeach policy each serilizer each service in
> backend do not forget this"

See `docs/TESTING.md`. E2E and QA are explicitly **later**, not never.

### R6 — Seeds, and write things down
> "add well seeds etc all with time and put info in claude or note some md file
> for problem its impoartant"
> "add these thing in your md files so you do not forget"

`db/seeds.rb` must produce a world you can actually place an order in.
Problems and lessons go in `docs/NOTES.md`; requirements go here.

### R7 — Push the work, keep pushing it
> "do git init and add git ingore etc" / "and push also" / "with time"

`github.com/Hama99o/karwan-api`, pushed as work lands rather than in one
lump at the end. The box hard-rebooted this morning and killed seven sessions.

### R8 — The name is Karwan. The old name is gone
> "make sure old name nervrer apear and how on app etc" / "and in doc and code"

A *karwan* is a company travelling together carrying **goods and people** — a
description of the platform, not a metaphor, which is why it survives the move
from food-only to food-plus-rides. Identical spelling in Pashto and Dari.

**Latin spelling is always `Karwan`** — never Karvan, Kaarwan or Caravan.
Persian و transliterates as both v and w and people will search all of them.

Renamed: the Rails module, the database names (dev, test and all four production
names), docker-compose, CI, Dockerfile, README, factories, docs. Verified by
`grep -rniI` returning nothing and by rebuilding the stack from scratch, not by
assuming. The dev and test databases were dropped and recreated — free now,
since both held zero rows, and not free later.

Built: commit renaming everything; database volume recreated as `karwan-api_postgres`.

### R9 — A merchant is a restaurant OR a store OR a bookshop, and also rides
> "like we should able to order from resurtant but it can be store or book store
> and for drive also"
> "for example send books etc"

The supply side was broadened three times in one hour. The schema now assumes
nothing about how many kinds there are:

- `merchant_kinds` is a **table**, not an enum. A bookshop is a row, not a
  migration. Seeded and translated, because the customer app renders these as
  browse labels in three locales.
- **Food-specific fields are nullable.** `merchants.prep_time_minutes` has no
  default and no presence validation, and `effective_prep_time_minutes` returns
  nil for a merchant that does not prepare food. A book is picked off a shelf,
  and defaulting it to 20 minutes would put a meaningless number on every
  bookshop that someone would eventually believe.
- `courier_profiles.accepted_job_kinds` is a **Postgres array with a GIN index**,
  reversing an earlier decision of mine to use one boolean per kind. Booleans
  were simpler to query and I preferred them, but a third demand type
  (person-to-person parcel) is already under discussion and a boolean per kind
  means a migration each time.

Built: `merchant_kinds` in `20260915120200_create_merchants`, array in
`20260915120500_create_courier_money`.

### R10 — Build it in the shape of the Asian super-apps
> "inspire from chines app like this or snap in iran etc"

Snapp (Iran) and Meituan (China): several services sharing one account, one
wallet and one fulfilment network, rather than several apps. This is the
justification for the whole polymorphic restructure — `offers`,
`status_transitions` and `wallet_entries` are polymorphic, and `Dispatchable`
holds what every demand type shares, so **nothing in the schema assumes exactly
two services.**

### R11 — Best possible mobile UI/UX; backend written to be understood and refactored
> "we should have like best ui and ux for mobile lmater for backend we should
> code it well so we understand well and we refactor and not bad code"

Mobile polish comes later, per the build phases. What it means for the backend
*now*:

- **Shared concerns instead of conditionals.** `Dispatchable`, `Monetary`,
  `SoftDeletable`, `TrigramSearchable`, `Roles`. Rules live in one place, so
  changing one changes it everywhere.
- **Namespace by role, never `if current_user.courier?`.** Per
  `docs/ARCHITECTURE.md`: duplication between roles is cheaper than coupling
  between roles, because roles diverge and conditionals never get removed.
- **Every non-obvious decision is a comment where the code is**, saying why and
  what the alternative cost. A decision recorded only in a commit message is
  invisible to the person reading the file.
- **Invariants are validations, not conventions** — money that does not add up
  cannot be saved.
- **Tests at every layer**, and every new gate proven to go red by planting the
  bug it should catch.

### R12 — Address voice notes, and the literacy constraint behind them
> `docs/AFGHAN_UX.md`, from "make sure it's easy for Afghan to use"

A large share of Afghan adults cannot read fluently, and the share is lower for
women and rural users. Typing "the blue gate near the mosque, second floor" in
Pashto is the hardest single action in the order flow; **saying** it is trivial.

So an address is **a pin, a voice note, and a phone number**, with the text
field optional rather than primary. `addresses` gained `has_voice_note` and
`voice_note_seconds` (queryable without loading the blob) plus an Active Storage
attachment, capped at 60 seconds — longer than that is a monologue, and a
courier will not listen to it at a junction.

Also found while doing it: **Active Storage was never installed**, though seven
`has_one_attached` declarations already existed. Nothing caught it, because the
macro does not touch the database and `zeitwerk:check` passes. Installed.

Still open from that document, and not yet built: Solar Hijri (Shamsi) date
rendering, Eastern Arabic numerals per locale (with phone numbers and order
codes staying Latin and LTR), and cross-script search — trigram similarity
cannot bridge `کباب` and `kabab`, so that needs a transliteration map or a
normalised search column. Recorded in `docs/NOTES.md`.

### R13 — For Afghanistan, but not technically restricted to it
> "remeber this app is only for afg but as we have done for hatiwal its open in
> side country pakistan but we did not mention it"

The market, the language, the money model and the whole of `AFGHAN_UX.md` are
Afghanistan. But the app is **not locked to it**, exactly as Hatiwal is not —
someone on a Pakistani or Iranian number can use it, and that is simply not
advertised.

Concretely, and verified rather than assumed:

- **No phone format or country validator anywhere.** `users.phone` is validated
  for presence and uniqueness only. A spec in `user_spec.rb` now asserts that
  +92, +98 and +93 numbers are all valid, specifically so nobody adds a `+93`
  rule in good faith and locks out everyone across the border.
- **No geofence and no country check** in any model or config.
- **Currency stays AFN-only for v0**, and that is not a contradiction: the
  `Monetary` concern is the single place a second currency gets added, and every
  amount already stores its currency explicitly. A PKR merchant later is an edit
  to `SUPPORTED_CURRENCIES`, not archaeology.
- **Map bounds are the one place this could bite.** `hatiwal-map` builds its
  tileset from an Afghanistan extract, so a courier just over the border would
  see no map. Recorded in `docs/NOTES.md` rather than solved, since the map
  decision is still Hamma9900's.

### R14 — Seeds must be big enough to stress test, not just to demo
> "the goal is like replication should be good the seed should be enough uh, big
> country so we can real uh, test like uh, stress test where we can see the
> pagination and everything is doing well in the live thing"

Two different seed jobs, and they should not be confused:

- **Sample** (`db/seeds/sample.rb`) — a small, hand-written world you can place
  an order in and read end to end. Every order state, every courier state, real
  Afghan dishes. For development and for looking at.
- **Stress** (`db/seeds/stress.rb`) — volume. Enough merchants, items, couriers
  and order history that pagination, indexes and the admin board are exercised
  under something like real load. Afghanistan is ~40m people; a neighbourhood
  in Kabul is the start, not the ceiling.

Opt-in and scaled by env var, because nobody wants 20k orders on every
`db:seed`. Uses bulk inserts, so it must not be trusted to exercise
validations — that is what the suite is for.

Built: `db/seeds/stress.rb`, `KARWAN_SEED_STRESS=1`.

### R15 — Live GPS tracking, visible to BOTH sides
> "if the order is taken the GPS system I don't know if uh, you have think about
> that it's important also to tracking the thing for both ... the client can see
> how it's going on, the user can see like everything this should be working
> also"

Both the customer and the merchant need to see where the job actually is, not
just what state it is in. A status list answers "has it left?"; a position
answers "where is it?", which is the question people actually ask.

What exists now: `courier_profiles.last_latitude/longitude/location_updated_at`
— one current position per courier, with `location_fresh?` refusing a fix older
than 5 minutes, because a stale fix is a memory and not a location.

What that is enough for: live tracking in v0. The customer app polls the
courier's current position while their job is active. **Foreground only, while
a job is active** — background location is explicitly out of v0.

What is NOT built, and needs deciding rather than assuming:

1. **Who may read a courier's position.** Only the customer and merchant of that
   courier's ACTIVE job, only while it is active, and never the whole fleet.
   This is an authorization rule, and the edu-safi lesson applies exactly:
   write the scope *and* use it, with a request spec proving both the refusal
   and the legitimate path.
2. **Position at the moments that get disputed.** Where the courier was when
   they marked picked up and delivered. Cheap to store, and it is the only
   evidence when a customer says the food never arrived. Recommended; not built.
3. **Breadcrumbs / route replay.** A position history per job. Genuinely useful
   for calibrating the ETA speed setting from real deliveries, which CLAUDE.md
   already calls for. v1 — it is a table and a retention policy, not a v0
   feature.

### R16 — Pricing and courier earnings are algorithms, and different per demand type
> "we will need an algorithm how we will decide how much we will give to person
> and how much we will [take]. Like how it will work, same for driving cars. So
> how it will work? Like there is will there will be different algorithm for
> driving uh, and rider."
> "You will check the professional application, and we will do same as they have
> done, and we will use same algorithm, everything."

**Deliveries and rides price differently, and this is already reflected in the
schema** — they are separate tables with separate money columns precisely so
the two algorithms cannot be forced into one formula:

| | Delivery | Ride |
|---|---|---|
| Customer pays | `items_total + delivery_fee` | `fare` |
| Priced from | flat fee (per-distance later) | base + per-km + per-minute, floored |
| Courier keeps | `courier_fee` | `fare − commission` |
| Courier advances | `merchant_payout` — out of their own pocket | nothing |
| We take | `commission` on the items | `commission` on the fare |

All of the inputs are already **Setting rows**, tunable with no deploy:
`commission_rate`, `delivery_fee`, `courier_fee`, `trip_base_fare`,
`trip_fare_per_km`, `trip_fare_per_minute`, `trip_minimum_fare`,
`trip_commission_rate`, `eta_average_speed_kmh`.

**No calculator is built yet**, deliberately — the numbers that decide it are
three of Hamma9900's own open questions (what a Kabul courier expects to earn
per day, what a customer will pay for delivery, how many orders ten merchants
actually sell). Writing a formula before those are known is guessing with extra
steps.

What the code must keep true whatever the algorithm turns out to be, and does:

- **Amounts are snapshots.** An order renders the numbers it was priced with,
  never a recomputation from today's settings.
- **The parts sum to the whole**, enforced as a validation, so no formula can
  produce a total nobody can explain at the door.
- **The server computes and sends totals.** Never assembled on the client.
- **Money is shown before it is owed** — the customer's total before ordering,
  the courier's advance before accepting, the commission before confirming.

On copying the professional apps: what is worth taking from Snapp, Meituan,
Uber and Careem is the **shape** — one wallet, one pool, prepaid commission,
distance-banded fares, a floor on short jobs, a visible quote before accepting.
What is not transferable is their **numbers**, which come from their own
markets and their own cost of living. Surge and incentive pricing in particular
are on the v0 OUT list and should stay there until utilisation is real and
measured.

---

## Relayed via Hamma9901 (supervisor), from Hamma9900's voice messages

> **Note on provenance:** these arrived as voice messages summarised by the
> supervisor session rather than as text typed by Hamma9900. The substance is
> his; the wording below is a relay, and short phrases in quotes are the ones
> the relay preserved verbatim. Flagged because everything else in this file is
> his own typing.

### R17 — The stakes, and why they are an engineering instruction
**"This is my last project."** Self-funded. He will not start another
application until Karwan earns money and pays for the software house he intends
to open. Hatiwal deploys first and gets its campaign; Karwan is announced to
that same audience immediately after.

He acquires every user personally — sitting with merchant owners, talking to
drivers, making videos. Nobody arrives through advertising. Two consequences
that belong in the code rather than in a pep talk:

- **The interface is the product.** In his words the simplest possible interface
  is *"the most important part"*. The person who convinced someone to install
  this is not standing next to them when they open it.
- **The pitch must be literally true.** What he is promising is one app where
  *"you search the driver, the driver comes to you, you sit, you go where you
  want"*, plus delivery in the same app. So dispatch and live tracking have to
  work on Afghan connections — not demo well. A correct backend is the promise,
  not the polish.

### R18 — Per-order marginal cost must be effectively zero
Because the money is his. Self-hosted tiles, self-hosted Nominatim, self-hosted
OSRM, FCM for push, Postgres for everything. **No metered third-party API on any
path an order touches.** Where two designs both work, the cheaper-to-run one
wins, and the monthly cost at 100 orders/day gets stated before committing.

The only real recurring costs in v0 are **the VPS and SMS**. That reclassifies
**OTP send throttling from a security gap to a bill** — an unthrottled endpoint
is someone else spending his money. Priority raised accordingly; it must close
before anything ships.

### R19 — Back office, partner statements, and a payment system built but switched off
The Administrate console must answer the business questions, not just list rows:
**how much have we earned, how many customers do we have**, and let an operator
change things.

Separately, **merchants and couriers each need their own earnings view** —
weekly earnings, and how much they owe the platform. For a courier that is
already the wallet balance; for a merchant, under Model A, the answer is
normally nothing, because they are paid in cash at every pickup. What they want
is a statement: sales, commission deducted, net received.

**A payment system present in the interface but disabled.** Not called, not
wired to a provider, but visible — so the screen exists and the flow is
understood before it is switched on. The schema already accommodates this:
`payment_status` is payment-method-neutral and `payment_method` is an integer
enum, so adding a method needs no migration.

**Recommendation, not yet built:** statements should be SNAPSHOT when issued,
not recomputed on demand. They are financial records shown to a partner, and a
later change to the calculation would silently rewrite what someone was shown
last month — the same argument that makes `order_items` a snapshot. `settlements`
already works this way.

### R20 — The pricing algorithm is the open question, and he knows it
His own framing: couriers pay the platform, and the question is *how* — "by
kilometers or another system", and how to propose the right price in the first
place. He is explicit that there is time to think and that he wants every idea
gathered rather than a formula guessed now.

What is already true in the schema, so no decision is foreclosed:

- Delivery and ride are separate tables with separate money columns, so the two
  formulas cannot be forced into one.
- Every input is a `Setting` row — tunable with no deploy.
- Every amount on a job is a **snapshot**, so changing the formula never
  rewrites a past order.
- `Merchant#commission_rate` overrides the global rate per merchant, so a deal
  struck with one restaurant does not move everyone else.

What is NOT decided and needs his numbers: whether courier commission is a
percentage, a flat per-job fee, or distance-banded; whether delivery fee varies
by distance; and where the floor sits on a short job. Three of the inputs are
his own open questions — what a Kabul courier expects to earn per day, what a
customer will pay for delivery, how many orders ten merchants actually sell.

### R21 — Work closely with Hamma9901, and document everything
> "make sure you work well with Hama 9901 which is important because he know
> everything" / "make sure we doc everything, we test everything. Documentation
> is very important."

Operationally: brief-versus-code conflicts go to Hamma9901 with the evidence and
a recommendation rather than being resolved silently; this file stays a verbatim
log; `docs/NOTES.md` carries every gap and lesson; and non-obvious decisions are
commented **where the code is**, because a decision recorded only in a commit
message is invisible to the person reading the file.

