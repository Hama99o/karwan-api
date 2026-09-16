# Karwan — Claude Workspace Instructions

>
> **This is one platform, two demand types, one app, two tabs** — food delivery and rides —
> sharing one courier pool, one wallet, one dispatch, one admin. Snapp's shape. The reason is
> **courier utilisation**: food demand is spiky, and two demand streams on one pool fill the
> idle hours, which is the number the whole business turns on.
>
> Sections below were written when this was food-only. Read them with that in mind; the
> corrections at the end of this file override anything that conflicts.

## Why this matters — read before you touch anything

Hamma9900's own words, twice over: **"this is my last project."** He is self-funding it. He
will not start another application until Karwan earns money and pays for the software house he
intends to open. Hatiwal ships first and gets its campaign; Karwan is announced to that same
audience immediately after.

He is not buying growth. He is going to sit with restaurant owners, talk to drivers, and make
videos himself. Every user arrives through a conversation he personally had. That sets the bar
in two places and you should feel both of them in the code:

- **The interface is the product.** In his words, the simplest possible interface is *"the most
  important part."* A first-time user on a cheap phone with a bad connection, who may not read
  fluently, has to get through it without help — because the person who convinced them to
  install it is not standing next to them.
- **The pitch has to be true.** What he is promising people is one app where *"you search the
  driver, the driver comes to you, you sit, you go where you want"* — and the delivery in the
  same app. Live tracking and dispatch have to actually work, on Afghan connections, or the
  campaign burns the audience he spent months earning. **A good algorithm and a correct
  backend are the promise, not the polish.**

And it has to be cheap to run, because the money is his. See corrections **6** through **12**
at the end of this file: they are the binding statement of the business model and they override
anything earlier that conflicts.

## Read these, in this order — all of it is binding

| Document | What it settles |
|---|---|
| **`CLAUDE.md`** (this file) | What Karwan is, the money model, the data model, the OUT list, the one-way doors. **The corrections at the end override anything earlier.** |
| **`docs/AFGHAN_UX.md`** | **Read this second.** How to design for Afghan users — literacy, the Shamsi calendar, voice notes, numerals, cheap phones, shared phones. It outranks generic mobile best practice wherever they conflict. |
| **`docs/SERVICE_TIERS_AND_BATCHING.md`** | Premium vs normal, and why the tier IS the consent for batching. |
| **`docs/DESIGN.md`** | How the mobile app looks: one component library in three modes, RTL-first, colour, type, density per role. |
| **`docs/ARCHITECTURE.md`** | How to structure four roles and two demand types without it rotting. Naming that must be right before there is data. |
| **`docs/PRODUCT.md`** | Screen-level spec per role, and the build phases. Build in that order. |
| **`docs/HOW_WE_WORK.md`** | What you decide, what comes to Hamma9901, what is Hamma9900's. Definition of done. The seven-question self-review. |
| **`docs/REQUIREMENTS.md`** | Hamma9900's own words, verbatim, as they arrive. Append, never summarise. |
| **`docs/NOTES.md`** | Known gaps and problems. Record them rather than carrying them in your head. |

Also read, before designing anything: `../../Hatiwal/CLAUDE.md`, `../../edu/CLAUDE.md`,
and `../../Hatiwal/hatiwal-mobile/qa/QA_HANDBOOK.md`. Take their patterns and discipline —
not every dependency.

## What this is

**Karwan** (کاروان) is a delivery and transport platform for **Afghanistan**, starting with
**one neighbourhood in Kabul**. Owner: Hamma9900 (Muhammad Hammayoun Safi), based in France,
building remotely.

A *karwan* is a company travelling together, carrying **goods and people**. The name is a
description of this platform rather than a metaphor for it, which is why it survives as the
scope grows — food, goods from any kind of merchant, rides, and whatever else needs carrying.
Couriers **travel with the karwan**; merchants **join it**.

- **Karwan** — one Latin spelling, never varied. Not Karvan, not Caravan.
- **کاروان** — identical spelling in Pashto and Dari, so one wordmark serves both locales.
- The old working name (the meal cloth) is **retired permanently** at Hamma9900's
  instruction. It should appear nowhere in code, config, database names or docs. If you find
  it, remove it — the only exception is `docs/REQUIREMENTS.md`, which is a verbatim log of
  his own words and must not be rewritten.

---

## V0 IS SIMPLE AND FUNCTIONAL

This is the most important instruction in this file. Every decision below is made to
keep v0 small enough to finish. **A shipped v0 beats a designed v1.**

The owner already has **two apps three months in and neither is in a store**. Do not
repeat that here. Prefer the boring option, ship it, then improve.

### In scope for v0

- One app, three roles (customer / restaurant / rider), with role switching
- **Cash on delivery only** — Model A, below
- One city, one zone, no zone logic
- Menu, order, dispatch (simple), delivery, cash settlement
- Admin dashboard to see and fix everything
- Android **and** iOS
- Pashto, Dari, English — with RTL for ps and fa

### Explicitly OUT of v0 — do not build these

- **No online payment.** No HesabPay, no cards. Cash only. Payment is v1.
- **No background location.** Foreground tracking only, while an order is active.
- **No routing engine, no drawn route.** ETA = straight-line distance ÷ average speed,
  calibrated from real deliveries. Add OSRM later if it is ever the bottleneck.
- **No dispatch optimisation.** No batching, no ML, no zones.
- **No street addressing.** See "The address problem" below.
- **No ratings/reviews** in v0.
- **No promo codes, surge pricing or loyalty.**
- **No separate apps per role.** One app. This is a firm product decision.

---

## Architecture

Mirror Hatiwal's shape. It works, the owner knows it, and the tooling transfers.

| Repo | Stack | Mirrors |
|---|---|---|
| `karwan-api` | Ruby on Rails, JSON API only | `hatiwal-api`, `edu-safi` |
| `Karwan-mobile` | React Native + Expo (SDK 54), Android + iOS | `hatiwal-mobile` |
| `Karwan-admin` | Admin dashboard | `hatiwal-web` / edu-safi admin |
| map | **reuse `hatiwal-map`** — see below | — |

Read `../../Hatiwal/*` and `../../edu/*` before designing anything. The owner's
instruction is to take inspiration **100%** from them — same patterns, same discipline,
same deploy pipeline (Kamal, EAS).

### The map — decision pending, lean toward extending

`../../Hatiwal/hatiwal-map` already builds and serves a self-hosted tileset:
**planetiler** from `afghanistan-latest.osm.pbf` (Geofabrik) → **go-pmtiles** →
**nginx** → **kamal-proxy** for TLS, with 8 style files (light/dark × en/fa/ps/ur) and
a runbook. Geocoding exists via Nominatim `countrycodes`.

**Preferred: extend `hatiwal-map` to serve both apps** rather than fork it. One tileset,
one deploy, two consumers. Add a Karwan style if the branding needs it.

**Critical trap already documented in that repo's runbook:** the `bounds` in
`build-styles.mjs` must match planetiler's `--bounds` exactly, or MapLibre asks for tiles
that do not exist. If a routing service is ever added it becomes a **third** consumer of
the same extract — build it from the same `.pbf` or you will route over roads the map
does not draw.

**GPS is not the map provider.** The phone's OS gives lat/lng via `expo-location`. No
provider, no cost, nothing to integrate.

**Offline tiles are a v0 requirement here, unlike in Hatiwal.** A rider in a stairwell or
a bad-signal street still has to see where they are going. Hatiwal has an open blank-band
bug caused by tiles failing on weak networks and never being retried — do not inherit it:
turn on MapLibre's ambient cache and pre-download the working city at z10–z15.

---

## The money model — Model A, decided

Worked example: food **400**, delivery fee **100**, commission **50**. Customer pays **500**.

1. Rider pays the restaurant **350** at pickup (400 food − 50 our commission)
2. Rider collects **500** from the customer
3. Rider keeps their **100** fee
4. Rider is left holding our **50**

**Why Model A and not "platform settles with restaurants weekly":**
- The restaurant is paid **instantly, in cash, every order**. That is the single biggest
  reason a restaurant signs up, and signing restaurants is the hardest problem.
- Our exposure per order is ~50 AFN, not ~450.
- We never owe restaurants money, so we can never fail to pay them.

### The rider wallet — prepaid, never a debt

Do **not** build a system that collects money from riders. Build one they prepay into.

- Rider deposits credit → balance
- Each delivered order **deducts** the commission
- Low balance → warn; zero → **the app stops assigning orders**
- New riders get a small **credit line** (e.g. −500 AFN) so they can start with nothing,
  and so a reconciliation delay never blocks them
- Raise the line with track record — it becomes a reason to stay

This inverts the incentive: we never chase anyone, because they cannot work without
credit. Afghans understand it instantly — it is how phone credit works.

### Top-ups

v0: **bank deposit referenced by a numeric rider code**, not a name. Names repeat and
transliterate badly (Muhammad/Mohammad/Mohammed); a 4-digit code survives. Admin
reconciles from the statement and credits the wallet.

Later: **HesabPay top-ups**. Note the reframe — HesabPay's real value here is **rider
settlement, not customer checkout**. 1,200+ agent locations, instant, machine-readable,
and a handful of transactions per rider per week so fees barely matter.

### Policies that must be data, not arguments at the door

Written, visible to the rider before their first shift:

- **Customer refuses the food** → **the platform absorbs it**, reimbursed to the rider the
  same day. The rider funded that food; losing 400 AFN through someone else's behaviour is
  how we lose riders, and they tell every other rider. Rider supply is the scarce side.
- **No change** → riders carry a change float.
- **Nobody home** → same as refusal.
- **Order cancelled after pickup** → rider reimbursed, same day.
- **Rider disappears with cash** → the wallet balance is the entire exposure, by design.

---

## Data model — v0

Enough detail to start. Extend, do not redesign.

### People and roles

- `users` — **phone number is the identity**, OTP login. Not email: everyone has a phone,
  few have email. Store `phone`, `name`, `locale`, and `last_active_role` —
  which mode a DEVICE is in lives on `user_sessions.active_role`, because one
  person's counter tablet and pocket phone can be in two modes at once. See
  `docs/NOTES.md`.
- `user_roles` — a user may hold several: `customer`, `rider`, `restaurant_owner`, `admin`.
  **One app, one account, switched roles** (Hatiwal's buyer/seller pattern, extended).
- `addresses` — belongs to user. See "The address problem".

### Restaurant side

- `restaurants` — name, phone, owner, `is_open` (manual toggle), opening hours,
  `prep_time_minutes`, location (lat/lng + pin), commission rate, status
- `menu_categories` — ordered
- `menu_items` — name, description, price, photo, `is_available` (sold-out toggle),
  category, prep time override
- `menu_item_options` / `menu_item_option_values` — size, extras, with price deltas.
  **This is bigger than it looks; keep it simple but do not skip it.**

### Orders

- `orders` — customer, restaurant, rider, `food_total`, `delivery_fee`, `commission`,
  `customer_total`, `payment_method` (`cash` in v0), `status`, **`cash_status`**,
  delivery address snapshot, customer phone snapshot, notes, timestamps per transition
- `order_items` — snapshot of name, price, options **at order time**. Never join live to
  `menu_items` for historical orders; menus change.

**Make `cash_status` an explicit column**: `pending → collected → settled`. "Has this
money reached me?" is asked a thousand times a day and must be a column, not a join.

### Order state machine — explicit, with a timeout on every step

```
placed → accepted → preparing → ready → picked_up → delivered
   ↘ rejected   ↘ cancelled (by customer / restaurant / admin)   ↘ failed (refused / no-show)
```

Every state needs: who can move it, a timeout, and what happens on timeout. An order
stuck with no timeout is a person waiting with cold food. Record the actor and timestamp
of every transition.

### Money

- `rider_wallets` — balance, credit line
- `wallet_entries` — rider, order, kind (`commission`, `top_up`, `reimbursement`,
  `adjustment`), amount, **who recorded it**, created_at
- `settlements` — expected vs **counted**, both stored, plus the named person who counted.
  Mismatches are normal; unexplained mismatches are theft.
- `payouts` — not in v0 (Model A means we never owe restaurants), but leave room.

Currency: **AFN only in v0**, and store it explicitly on every amount. Never sum across
currencies — edu-safi shipped a bug that added afghanis to dollars in one total.

### Config, not constants

Commission %, delivery fee, rider fee, cash-in-hand limit, credit line, ETA average speed
— **all settings rows, editable by admin**. These get tuned weekly. Hard-coding them means
a deploy every time the owner changes his mind about a number.

### Audit

Every money-touching action and every admin intervention: actor, action, before, after,
timestamp. Non-negotiable.

---

## The three roles — one app, completely different designs

The owner wants **one app** where Uber and Deliveroo ship three, with an **advanced role
switching system**, and **each role's design completely different**. Take Hatiwal's
buyer/seller mode switch as the starting pattern and go further.

- **Customer** — browse restaurants, menu, cart, place order, track, order history.
  Warm, photo-led, the most polished surface.
- **Restaurant** — a workbench, not a shop. Incoming order alert, accept/reject, mark
  ready, toggle items sold out, open/closed. Big touch targets, minimal chrome, readable
  across a room. **Must work on a cheap tablet propped on a counter.**
- **Rider** — a tool used one-handed, in motion, in sunlight. Available/offline toggle,
  the assigned order, navigation, collect cash, wallet balance, top-up. High contrast,
  huge buttons, almost no text.

Role switch must be obvious and fast, and the app must remember the last role per user.

---

## Dispatch — the hard part, kept crude in v0

There is no prior art for this in any of the owner's codebases. Keep it simple:

1. Order accepted by the restaurant
2. Offer to the **nearest available rider whose wallet can fund the food**
3. **Timeout** (e.g. 60s) → offer to the next
4. After N riders decline or time out → surface to admin to assign by hand
5. Admin can always reassign

That is it. No batching, no optimisation, no zones. Build the manual override **first** —
it is what makes the business operable while the automation is wrong.

---

## Things that will bite you — learned expensively elsewhere today

These are real, from Hatiwal, edu-safi and multi_magic. Read them before writing code.

**Read what is already there before deciding anything.** Nine times in one day in
Hatiwal, the answer to a bug was already written in the file — a helper comment naming
its own victims, a Rails log, a passing sibling assertion, an i18n key two lines up.
**But** a nearby comment can be stale and believed anyway, and a correct premise can still
reach a wrong fix. Read first, verify second.

**A check that cannot fail is worse than no check.** Five separate instances in one day:
four vacuously-green test suites, a structural checker blind to its own blind spot, a lint
gate that inspected only `spec/`, another whose cops were 726-disabled, and a lint run
that passed because it silently skipped a whole cop family. **Prove every gate can go red
by planting the bug it should catch.**

**Verify at the layer where it lands, not where you are looking.** multi_magic shipped a
screen that blanked on first use. Request specs were green, `tsc` was green, and nothing
rendered the component. Also: **a typed `http.get<T>` is a cast, not a validation** — the
interface is your own assertion about runtime shape, so it agrees with itself while being
wrong.

**Android modals hide toasts.** `sonner-native` wraps the Toaster in `FullWindowOverlay`
on iOS (a separate window, above everything) but not on Android, where a `<Modal>` is its
own native window and covers it. So an error toast fired while a sheet is open is
**invisible on Android and fine on iOS**. This app is full of sheets. Render errors
**inline** in the sheet, and gate Android-only fixes on `Platform.OS`.

**A defect behind a disabled control is not a defect.** Before counting an error path as a
bug, ask whether a user can reach it.

**Mobile QA specifics** (if you adopt Hatiwal's Maestro rig, which you should):
`assertVisible` never scrolls; a `scrollUntilVisible` that succeeds leaves the list where
it stopped and every later command inherits the offset; **a tap that lands on the keyboard
is reported COMPLETED**; never tap a field's own content to focus it (the caret lands
mid-string); read the **bounds**, not just node names — a five-pixel-tall input explains
what no amount of waiting will; and a shared login helper can leave a flow signed in as
the wrong user, which presents as missing buttons.

**i18n**: a plural-only key with no base form renders the raw key on screen. Pass the
**number** for plural selection and the **formatted value** separately. Add keys to all
locales or parity checks lie. For RTL use **logical** spacing utilities, not physical, and
mirror directional icons — a correct `dir` with a left-pointing "next" arrow is still wrong.
Pashto and Dari strings run longer than English; layouts that pass in English will break.

**Authorization**: `current_organization` is tenancy, **not permission**. edu-safi had five
endpoints where the correct scope existed, was correct, and was never consulted. Write the
scope *and* use it, and add a request spec proving both the block and the legitimate path.

**Never sum across currencies.** Group by currency.

**Commit per finding.** The box hard-rebooted once today and killed seven sessions; the one
that lost nothing was the one committing as it went.

---

## The address problem

**Do not build street addressing.** Afghan addresses are unreliable and people navigate by
landmarks. Instead:

- A **pin on the map**, dropped by the customer
- A **free-text landmark note** ("blue gate near Shar-e-Naw park, second floor")
- A **phone number**, always

Reverse geocoding is a nicety, not the mechanism.

## Notifications that must arrive

A missed "new order" alert is a lost order, not an annoyance. Cheap Android with aggressive
OEM power management will drop pushes.

- Restaurant: **loud, repeating, until acknowledged.** Assume a tablet on a counter in a
  noisy kitchen.
- Fallback when push fails: in-app polling while the app is open, and an SMS or phone call
  path for the restaurant.
- Never rely on a single delivery mechanism for the restaurant alert.

## Support is a human, and the app must admit it

Put a **phone number in the app** for all three roles. Delivery is an operations business
with an app attached; when an order goes wrong someone has to fix it now, in Dari, in Kabul.
Build the admin tools that let that person act: reassign a rider, cancel an order, credit a
wallet, mark an order failed — **every one logged with who did it**.

---

## Open questions — Hamma9900's, not ours

Do not start work that depends on these. Ask, then proceed.

1. **Map: extend `hatiwal-map` to serve both apps, or fork it?** Recommendation: extend.
2. **The three numbers that decide the unit economics**, none of which we know:
   - what a Kabul rider expects to earn per day
   - what a customer will actually pay for delivery
   - how many takeaways ten local restaurants sell per day
   At ~13 orders/rider/day the delivery fee pays the rider and no subsidy is needed. Below
   that, every order loses money. **This decides whether dispatch matters at all.**
3. **Can he hold an Afghan bank or HesabPay merchant account from France?** If not, the
   money sits in a local partner's name — a trust question, not a technical one.
4. **Who is the trusted person in Kabul** who signs restaurants and manages riders? Nothing
   operational works without them, and no code substitutes.

---

## How to work here

- Read `../../Hatiwal/CLAUDE.md`, `../../edu/CLAUDE.md` and the Hatiwal QA handbook
  first. Steal patterns, discipline and tooling — do not reinvent.
- **Commit per finding**, with a message that says what changed and why.
- Every authorization or payload change needs a **mobile check in the same pass**; the
  mobile app calls the same endpoints.
- State plainly what you verified and at which layer. "Verified on Android, reasoned for
  iOS" is an honest sentence; "tested" is not, when there is no Mac here.
- Report to **Hamma9901** (the supervisor session) — it coordinates the other sessions,
  watches RAM/CPU, and takes decisions to Hamma9900. Do not go idle: when you finish a
  piece, start the next one.
- If something is genuinely the owner's decision, say so and keep working on what is not.

---

## One-way doors — get these right now, everything else can wait

The owner's stance is explicit and correct: **v0 will miss things, and we come back and
change the backend into something usable over time.** Build accordingly — small, plain,
easy to replace.

**But distinguish the reversible from the irreversible.** Almost everything is reversible:
fields, tables, endpoints, roles, states, prices, rules, whole screens, even the payment
provider. Rewrite any of it later.

**These six are not.** Get them right on day one, because what you fail to record cannot
be reconstructed:

1. **Snapshot order lines.** `order_items` stores the item name, price and chosen options
   **as they were at order time**. Never join a historical order to live `menu_items` — a
   restaurant editing its menu would silently rewrite last month's orders.
2. **Currency on every amount.** One column, from the first migration. Without it a second
   currency is impossible to add safely, and totals across currencies are a bug that has
   already shipped in this owner's other app.
3. **A timestamp per state transition**, not just the current `status`. "How long do orders
   sit in preparing" is the metric that runs a delivery business and **cannot be backfilled**.
   Record the actor too.
4. **Every money movement as a ledger entry, written at the moment it happens.** A balance
   can always be recomputed from entries; entries can never be reconstructed from a balance.
5. **An audit row for every intervention** — who reassigned, who cancelled, who credited a
   wallet, before and after. Unanswerable later if nobody wrote it.
6. **Soft delete, never hard**, for restaurants, riders, menu items and addresses. A deleted
   record with live order history is a hole in the books.

Everything else: build the simplest thing that works, ship it, and change it when reality
tells you what it should have been.

---

## Corrections to this brief — these override anything above

Learned from the real code and from Hamma9900 directly, after this brief was written.
Where they conflict with an earlier section, **these win.**

**1. The admin lives INSIDE the API repo, not in a separate one.** The architecture table
above lists a `Karwan-admin` repo. Wrong. `hatiwal-api` actually runs **Administrate**
inside the API repo (`app/dashboards/`, `app/controllers/admin/`, `AdminAuditLog`) despite
its own CLAUDE.md claiming the dashboard was never built. Hamma9900 has settled it:
**Administrate, in `karwan-api`. One repo, one deploy.**

**2. Do NOT use `devise_token_auth`, even though `hatiwal-api` does.** It authenticates on
an **email uid**, which is incompatible with phone-as-identity — it would mean synthesising
a fake email for every Kabul customer. **Phone + OTP is the product requirement and it beats
the reference implementation.** Built instead: bcrypt-digested OTP codes and HMAC-digested
session tokens.

The general rule this establishes, which matters beyond auth: **"mirror Hatiwal" means take
its patterns and discipline, not its every dependency.** Where a Hatiwal choice contradicts
a stated product requirement here, the requirement wins — say so rather than bending the
product to the reference.

**3. No Redis.** All three solid-queue/cache/cable adapters run on Postgres, so Redis was a
container and a gem earning nothing. Dropped.

**4. The model count in this brief is a floor, not a ceiling.** The v0 list sketches ~15
tables; the real schema is ~25, and the extras are this brief's own sentences made storable
— OTP needs somewhere to put codes and sessions, "options at order time" cannot live in a
column, "a timestamp per transition" is a table, dispatch with a 60-second deadline is a
table, opening hours are rows. Plus a global **cuisine taxonomy**, which Hamma9900 asked for
separately: `menu_categories` is one restaurant's own menu structure and is not browsable
across restaurants, so cross-restaurant food search needed its own thing.

**What still matters is the OUT list, not the table count.** Nothing from it is modelled —
no payments, no zones, no routing, no ratings, no promos, and `payouts` is deliberately
absent because Model A means we never owe restaurants money.

**5. Requirements arriving mid-build go in `docs/REQUIREMENTS.md` verbatim**, with what each
one means for the code. Problems and known gaps go in `docs/NOTES.md`. Hamma9900 directs in
real time and nothing should depend on a supervisor relay to survive.

**6. Money is the binding constraint, and it is Hamma9900's own money.** He is self-funding
this, launching by talking to restaurants and drivers himself and making videos. Read that as
an engineering instruction, not background: **the per-order marginal cost must be effectively
zero.** Self-hosted tiles, self-hosted Nominatim, self-hosted OSRM, FCM for push, Postgres for
everything — no metered third-party API on a path an order touches. When you are choosing
between two designs, the cheaper-to-run one wins unless the expensive one is the only one that
works. Say what a choice costs per month at 100 orders a day before you commit to it.

The only two real recurring costs in v0 are **the VPS** and **SMS for OTP**. That makes OTP
send throttling a bill, not just a security gap — an unthrottled endpoint is someone else
spending his money, and it is the reason that gap must close before anything ships.

**7. A ride and a delivery are two different job shapes, and that is a product fact.**
Hamma9900's framing, in his words: a ride *"is like a delivery, but we don't need a
restaurant"*; a delivery *"needs a restaurant or a store or a place."*

| | Legs | Money at each step |
|---|---|---|
| **Delivery** | to merchant → **merchant handoff** → to customer → customer handoff | courier **advances** the goods total minus commission, then collects the customer total |
| **Ride** | to passenger → passenger aboard → to destination → complete | courier collects the fare, advances nothing |

Two consequences, and getting these wrong is expensive:

- **The courier advances money on a delivery and nothing on a ride.** So the wallet check
  before a delivery offer asks "can this wallet fund the advance?", while before a ride offer
  it asks only "is this wallet above zero?" A ride is fundable by a courier a delivery is not.
- **One active-job screen, not two.** The courier app renders an **ordered step list supplied
  by the serializer** — each step a location, an action, and optionally an amount. A delivery
  serialises four steps, a ride three. This is not speculative generality: it is how a third
  demand type later costs a step list rather than a new screen, and it keeps `if food` out of
  the mobile code. `Order` and `Trip` stay separate tables; only the courier's view unifies.

**8. Model A applies to rides too — same wallet, same commission, simpler flow.** His words:
*"for the driver also for the store system, we will put same model."* The courier collects the
fare in cash, keeps it, and owes commission on it, deducted from the same prepaid wallet that
governs deliveries. **One wallet per courier across both demand types** — that is the whole
reason the pool is shared. No separate ride wallet, no separate ledger.

**9. Vocabulary: one word for the person, two for the job.** Hamma9900 says *driver* for the
ride courier and *rider* for the delivery courier. In code both are **`courier`** — a single
pool is the business thesis, and the same person takes a ride at 08:00 and a delivery at
13:00. The distinction he is drawing is between **job kinds** (`delivery` / `ride`), not
between two kinds of people. Keep `courier` for the person, and use his words in the UI copy
where they read naturally to an Afghan user.

**10. The customer login must be the simplest thing in the app.** Phone, OTP, in. No email,
no password, no profile-completion wall, no "create an account" framing before they have seen
a single restaurant. Let them browse before they log in and ask for the phone number at the
cart. A login screen is where a first-time user with a cheap phone and a bad connection gives
up, and he is acquiring these users one conversation at a time.

**11. The testing bar, in his words: every method, every function, every controller.** Not
coverage theatre — the money paths, the state transitions and the authorisation boundaries
carry real consequences. A controller without a request spec covering both the happy path and
the forbidden path is not done. See `docs/TESTING.md` for the contract.

**12. Launch order: Hatiwal first, then Karwan.** Hatiwal is near production and will be
announced first; Karwan is announced to the same audience afterwards. So Karwan gets the
benefit of Hatiwal's real deployment lessons — take them rather than rediscovering them — and
the shared map service must not be destabilised by Karwan's needs while Hatiwal is launching.
Extend `hatiwal-map`, keep it backwards compatible, add OSRM alongside rather than in place of
anything.

**13. Pricing stays deliberately stupid in v0, and admin-tunable.** His instruction: no deep
algorithm work now, because the mobile app and the map still have to be built. Both formulas
are two-part tariffs reading `Setting` rows, so he retunes prices from the admin console with
no deploy:

- **Delivery fee** = base + (per-km × merchant→customer distance), floored at a minimum.
  Revenue is the **commission** on the items total, per merchant.
- **Ride fare** = base + (per-km × distance) + (per-minute × duration), floored at a minimum.
  Revenue is a commission on the fare.

**The ride fare is quoted upfront and frozen on the trip, never metered.** This is a market
call, not a shortcut: an Afghan passenger already agrees a price with a taxi driver *before*
getting in, and a meter whose arithmetic the passenger cannot verify is exactly the trust
problem this platform exists to solve. Upfront pricing also deletes a whole class of work —
no live meter, no recalculation, no fare disputes.

**Deliberately OUT of v0 pricing,** and each costs one config row or one multiplier when it is
wanted: surge or time-of-day multipliers, zones, vehicle classes (he raised *"the car should be
checked also"* — that is a `vehicle_type` multiplier defaulting to 1.0, later), traffic-aware
duration, waiting time, multi-stop, promo codes, per-courier rates. Do not build any of them
now. **Do** keep the frozen-amount discipline that makes adding them safe: every amount is
written onto the order or trip row at the moment it is quoted, never recomputed for display.

**14. No third-party API on any path an order touches — and the two honest exceptions.**
Hamma9900's instruction: no Google, no keyed API, *"everything will be coded by us."* He also
said to correct him if he is wrong, so this states the rule precisely and then names what it
cannot cover.

**The rule.** Nothing metered, nothing keyed, nothing that can raise its price or revoke
access. No Google Maps, no Mapbox, no third-party geocoder, no routing API, no hosted search,
no analytics SDK, no crash reporter that phones home.

**The distinction that makes this achievable: self-hosted open source is not a third-party
API.** We run OpenStreetMap data, planetiler, go-pmtiles, OSRM, MapLibre, nginx, Postgres,
Rails and Expo. We did not write them and we are not going to — writing a routing engine
instead of running OSRM is months of work for a worse result. What matters is that they run on
**his** VPS, with no key, no per-request bill, and no company able to cut us off. That is what
"coded by us" has to mean in practice, and by that standard the map stack already qualifies:
measured marginal cost per order, zero.

**Exception 1 — SMS for OTP. Unavoidable, and it costs real money per message.** Delivering a
text to an Afghan phone requires a carrier or an SMS gateway. There is no self-hosted
substitute. This is the one true per-unit cost in v0, which is exactly why **OTP send
throttling is a billing control, not just a security control.** Choose the gateway on price per
message to Afghan networks and keep the sending behind one adapter class so it can be swapped
in an afternoon.

**Exception 2 — push notifications. FCM, which is Google.** Android push delivery goes through
Firebase Cloud Messaging; iOS goes through APNs. Neither can be self-hosted — the OS itself
holds the socket. It is free and not metered, but it is a Google dependency and Hamma9900
should know it exists rather than discover it. The mitigation is already in `PRODUCT.md`:
**never rely on one mechanism for the merchant alert** — push, plus in-app polling while the
app is open, plus an SMS or phone path. A missed alert is a lost order, so push is one of three
channels rather than the channel.

Everything else — tiles, styles, fonts, routing, geocoding-if-ever, search, ETA, tracking,
reporting — is ours and self-hosted. If a proposal introduces a third dependency, it comes to
Hamma9901 before any code is written, with its monthly cost stated.

**15. HATIWAL IS THE TARGET. DO NOT INVENT.** Hamma9900's standing instruction, given
emphatically and to be treated as outranking your own judgement about what would be better:
*"We did not decide anything. Do not invent anything. Hatiwal is our copy, our target."*

This is not a style preference. `hatiwal-mobile` and `hatiwal-api` are in production with real
users, and every pattern in them has already been paid for in debugging. A fresh design,
however clean, starts that bill again.

**So the default answer to "how should this work?" is: the way Hatiwal does it.** The theme
system, the language and i18n system, the login and session handling, the component structure,
the api layer, the stores, the hooks, the test layout, the build and EAS config — copy the
mechanism, keep the file names, keep the conventions. Where Karwan's product differs, change
the **values and the content**, not the **shape**.

**Before writing any new mechanism, go and look.** Read the Hatiwal file that does the nearest
thing, and say which file you read. "I could not find one" is an acceptable answer only after
looking. Inventing something Hatiwal already solved is the single most expensive mistake
available in this project, because it is invisible until it breaks differently.

### The honest boundary, because "copy Hatiwal" cannot cover everything

Some of Karwan does not exist in Hatiwal at all: **routing and OSRM, the courier wallet and
ledger, dispatch and offers, cash collection and settlement, four roles in one app, the
role-switching, and the courier's map view** — Hatiwal's map is a search surface and ours is a
navigation surface, which Hamma9900 called out himself.

For those, the rule becomes: **copy the nearest Hatiwal mechanism for the plumbing, and bring
the genuinely new part to Hamma9901 before building it.** A wallet ledger has no Hatiwal
equivalent, but it is still a Rails service object, a store and a screen — and those shapes are
Hatiwal's. So the new thing is the rule, not the architecture around it.

**Never invent silently.** If there is no precedent, say so, say what you propose, and say what
it costs — then wait. The two wrong moves are inventing a mechanism Hatiwal already has, and
inventing one it does not have without saying so.

**16. There is NO web app. Two deliverables only: the API (with its admin) and the mobile app.**
Hamma9900, explicitly: *"we don't do web for this app, only api has admin part and mobile."*

So the whole project is:

| Repo | What it is |
|---|---|
| `karwan-api` | Rails API **plus** the Administrate ops console, server-rendered, browser-only |
| `karwan-mobile` | Expo app, three role modes — customer, merchant, courier |
| `karwan-map` | a worktree of the shared map service, not a product |

**Do not create `karwan-web`.** Hatiwal has two separate things — `hatiwal-web`, a public web app,
and the Administrate console inside `hatiwal-api`. Karwan takes **only the second**. No customer
web ordering, no merchant web dashboard, no marketing site in this repo, no separate frontend
build, no second deploy target. If a screen is needed for a human at a desk, it is an
Administrate page inside the API.

**The useful consequence:** the admin console is the one surface where none of the mobile
constraints apply. It is a laptop on a desk, so it may be dense, table-heavy, keyboard-driven
and English-only if that is faster for Hamma9900 to operate. `AFGHAN_UX.md` governs the phone,
not the ops console — do not spend effort on RTL, photo-led layouts or 64dp touch targets there.

**There is also no admin role in the mobile app.** The role switch offers customer, merchant and
courier only. Nothing that can credit a wallet or cancel an order exists on a phone that gets
shared or lost — which matters in a cash business.

**17. NO MOCKS IN THE APP. The screens always talk to the real API.** Hamma9900:
*"we should not have mocks man"* — said after finding five mobile screens running on
`demoFetch`. He is right, and the reasoning is stronger than a preference:

**Fake data is now the most misleading state the app can be in.** The backend is
feature-complete — 929 examples green, 35 controllers — so a screen on demo data boots
looking like it works while proving nothing. It hides the only things still worth finding out:
whether the client parses real payloads, whether auth actually flows, whether the offline path
triggers on a real timeout. **An app that looks broken is more useful than one that looks
finished and isn't.**

So: no demo module, no fixture data, no hardcoded sample arrays, no fake server, no
"temporarily returning a stub until the endpoint exists" — if an endpoint does not exist yet,
the screen shows its real empty or error state, which is a state that has to work anyway.

### The honest exception: test doubles in tests

Hamma9900 asked to be corrected when he is wrong, and taken literally this rule would forbid
unit testing. You cannot test an HTTP client without controlling its transport, and a Node test
environment cannot load native fonts. So `src/__tests__/mocks/googleFontsStub.js` is
legitimate, and stubbing a transport in a spec is legitimate.

The line is: **a double may stand in for the outside world in a test. It may never ship inside
the app.** And a double must never stand in for the thing under test — `docs/NOTES.md` already
records that trap as *"a check that cannot fail is worse than no check"*, and a test that mocks
its own subject is exactly that.

**The measure to hold:** if the API is unreachable, every screen must show a real failure or a
real last-known state. If any screen still shows content, something is faking — find it.

**18. THE APPS MUST STAY SEPARABLE. One identity, one backend, four client apps that can be
split apart later without a rewrite.** Hamma9900, planning ahead: *"we will not mix the apps,
that's important. Imagine I have 10 million users and I want to separate the apps to 3 or 4 —
delivery and driver and client and restaurant or store. It should be easy. If we mix it, it can
make problem."*

He is right, and this is what every platform at scale does: Uber, Grab and Gojek all run one
backend behind separate rider, driver and merchant apps. So:

**WHAT SPLITS LATER: the mobile apps.** Customer, courier (delivery), courier (ride) and
merchant could each become their own binary in their own store listing.

**WHAT NEVER SPLITS: the backend.** One API, one courier pool, one wallet, one dispatch, one
admin. Splitting that would destroy the business thesis — courier utilisation across two demand
streams is the number this company turns on, and two backends means two pools.

**WHAT NEVER SPLITS: the identity.** One person, one phone number, one `users` row, several
`user_roles`. A courier orders food; a restaurant owner takes taxis. The platform must always
know they are the same human — that is also how a courier's wallet stays one wallet.

### What separability demands of the code, concretely

The test for every decision: **could this role's screens be lifted into their own Expo app
tomorrow, changing only the entry point?** If the answer is no, the coupling is the defect.

- **Shared, and safe to share:** the primitive library, the theme tokens, i18n, the HTTP client,
  the auth and session store, the map component. These are infrastructure — four apps would each
  import the same ones.
- **Never shared between roles:** screens, flows, role-specific stores, role-specific API
  modules. A customer screen must never import from `screens/courier/`, and no shared module may
  branch on role. ARCHITECTURE.md already says duplication between roles is cheaper than
  coupling between roles; this is the reason, stated in money.
- **The API namespaces are already right** — `api/v1/customers/`, `/merchants/`, `/couriers/`,
  `/public/`. A split app calls the same namespace it calls today, so the backend needs no change
  when it happens. Keep them strictly separate; never a shared controller that serves two roles.
- **Route groups are already right** — `app/(customer)/`, `(merchant)/`, `(courier)/`. Each group
  is the seam a split would cut along. Nothing outside a group may reach into it.

### The login flow he specified

One identity, but the role is chosen **at sign-in**, not discovered afterwards:

- **Customer is the default and is never asked.** A first-time user signs in and is a customer.
  Asking "what are you?" of somebody who wants a kebab is a question that loses users.
- **A second, quieter action — "Sign in as partner"** — then choose: restaurant/store, delivery
  rider, or taxi driver. The words are his: *"login as business or etc, and when we click we
  choose login as how — restaurant or rider or driver."*
- The chosen role is per **session**, not per person (correction on `active_role` in
  `user_sessions`), so three phones can hold three roles at once and one phone holds one.
- A person who does not hold the role they picked is told so plainly and offered the application
  path — that is the entry point to courier onboarding.

**This also answers the PIN question:** choosing a money-handling role at sign-in IS the gate, so
a separate in-app PIN is only needed for switching roles inside a session, not for entering one.

**19. MULTI-JOB IS COMING, AND NOTHING BUILT NOW MAY FORECLOSE IT.** Hamma9900 has called this
**the most important thing**: a courier carrying **several jobs at once** — food from two
restaurants on one run, or two passengers sharing a car — plus a passenger count that affects
price, and a cheaper **shared pickup** option.

It is not in v0, because it needs concurrent demand that one neighbourhood will not have on
launch day. **But it is the next major feature, and that makes it a design constraint on
everything being built now.** Same posture as correction 18: we do not build four apps, and we
never write code that would make splitting them a rewrite.

### The test to apply to every decision, starting today

> **Could this become "a courier holds a BATCH of jobs" without rewriting the money paths?**

Where a 1:1 assumption is cheap to avoid, avoid it. Where it is not, **write down that it is
there** so the batching work knows where to look instead of discovering it.

### What batching will touch, named now so it is not a surprise

- **`Dispatch::Eligibility`'s `:already_on_a_job`.** The guard is the correct v0 shape and stays.
  But the unit of assignment becomes a **batch**: "one live batch, and a job may only join a
  batch compatible with it." Keep the guard's query shaped so its subject can change from a job
  to a batch — and do not scatter the 1:1 assumption into other call sites.
- **Model A's cash, which is the hard part.** Today the courier advances **one** merchant payout
  and collects **one** customer total. Batched, he advances the **sum** of two payouts, carries
  two customers' cash, and `cash_in_hand_limit` starts binding far earlier. So: **every wallet
  and cash check must be expressible over a set of jobs, not only over one.** `can_fund?(job)`
  taking a single job is the exact shape that will need changing — when you touch it, leave the
  arithmetic summable rather than per-job.
- **Route ordering.** Two pickups and two dropoffs is a sequencing decision, and wrong means
  cold food and a waiting passenger. The courier's step list is already **server-supplied
  data** rather than client logic (correction 7) — which is why batching is a longer step list
  rather than a new screen. **That decision is what makes this tractable; do not undo it.**
- **The passenger count** is in v0 and is the first piece of this: a capacity axis for people
  beside the cargo axis, filtering which vehicle classes a passenger may choose.

### Hamma9900's privacy rule, binding from the first line of batching

**In a shared job, neither customer sees anything about the other** — not a name, not a phone,
not an address, not their stop. The courier sees both legs; each customer sees only their own.
Saying "we are three people" must never reveal who else is in the car. If that is not designed
in from the start it leaks through a serializer, and it leaks to two people who live in the same
neighbourhood.

### Honest note, recorded rather than used as an argument

Pooling is among the hardest products in this domain and Uber withdrew Pool from many markets
because the economics are brutal. **That is not a reason not to build it** — shared taxis are
normal in Kabul in a way they are not in London, and Hamma9900 knows his market. It is a reason
to build it when there is demand to fill, and to keep the v0 paths from making it a rewrite.
