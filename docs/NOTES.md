# Notes — problems, traps and lessons, written where the next person will hit them

Append-only. Newest at the top of each section. If something cost time, it goes
here with the evidence, not the recollection.

Two rules from the wider workspace that apply to this file:
- **Write the lesson down where the next person will hit it**, not just the fix.
- **A comment can be stale and still be believed.** Read first, verify second.
  If you find an entry here that no longer holds, correct it in place and say so
  — a wrong note left standing is worse than no note, because someone acts on it.

---

## Open problems — not yet fixed

> **Current as of 2026-09-16, 01:00.** A stale gap list actively misdirects —
> it sends the next person to fix something already fixed and lets something
> real sit. Everything below has been re-checked against the code, not
> remembered.

### EVERYTHING STILL OPEN NEEDS HAMMA9900, NOT CODE

The backend is functionally complete for v0: 1,040 examples, rubocop and
brakeman clean, every screen the app has is served. What remains is not
engineering:

| Open | What it needs | Why it cannot be decided here |
|---|---|---|
| **SMS gateway** | His choice and his money | The one true per-unit cost in v0. The adapter seam and the message exist (`Notifications::SmsClient`, `Setting` rows per locale); `SMS_PROVIDER=log` writes codes to the log, and `bin/preflight` warns that nobody can sign in that way. Choosing a gateway is an afternoon. |
| **VPS and deployment** | A host and a DNS record | `config/deploy.yml` is written and parked: a fourth service on the existing OVH box, Postgres on 5435, no Redis. Nothing is deployed. |
| **The support phone number** | One row in the admin console | `/public/app_config` serves it and every installed app picks it up with no rebuild. Blank today, so the app correctly hides the button. |
| **Pashto and Dari OTP copy** | Two rows in the admin console | An SMS has no device to translate it, so the server holds the words. English placeholders ship until he pastes the real text. |
| **New-courier credit line and the guarantor policy** | His numbers | `default_credit_line` is a `Setting` at 500 AFN, chosen as a placeholder. |
| **OSRM distance for pricing** | His decision | Routed distance raises fares ~29%. `routing_distance_source` defaults to `straight_line`; switching it is one row, no deploy. |
| **Renaming the karwan-api GitHub repo** | His account | — |

Two things are deliberately OUT rather than open: **the ride product**
(PRODUCT.md — "do not build the ride product yet"; the model, the pricing and
the courier's ride flow exist, the passenger endpoints do not) and **merchant
self-service profile editing** (PRODUCT.md — "not self-serve in v0, admin
onboards restaurants").


### Found by wiring the mobile screens — three gaps, three lessons

Every one of these was invisible from the server side and obvious the moment a
screen asked for it. Worth recording as a method, not just as fixes: **the
client is a test the specs cannot write.**

1. **The merchant board dead-ended at `accepted`.** `Order::TRANSITIONS` goes
   accepted → preparing → ready and there was no route to `preparing`, so the
   only button an accepted order had answered 422 `invalid_transition`. 965
   examples were green over that hole because every spec that exercised `ready`
   set the order to `preparing` by hand first. **A spec that arranges its own
   precondition cannot notice that nothing else can produce it.** Fixed:
   `POST /merchant/orders/:id/preparing`, plus a spec asserting the two
   transitions stay separately timed.
2. **The board card had no money.** `items_total` and `merchant_payout` were on
   the detail view only, so a card carried a code, an age and an item count. A
   merchant cannot tell a 180 AFN order from a 920 AFN one, which is the first
   thing they want to know. Added to `:board`.
3. **`OrderPolicy#track?` was written, correct, and dead.** Nothing called it —
   the same shape as the edu-safi lesson at the bottom of this file. It is why
   the customer's map had no data source: the order serializer carries the
   delivery pin but never the merchant's and never the courier's position.
   Fixed: `GET /customer/orders/:id/track`. Also added
   `spec/policies/order_policy_spec.rb`, because **a request spec proves the
   endpoints that exist behave, and says nothing about a predicate nothing
   calls.**

### The API bound port 3000 unless someone remembered `-p 3017` — CLOSED

Rails ships `port ENV.fetch("PORT", 3000)` and **3000 on this box is a
different live application**. So the API only landed on 3017 when whoever
started it remembered the flag, and when they did not, a health check reported
a **green API that was a stranger's** — `qa.sh doctor` did exactly that.

The convention lived in the README, which is why it was missed. It now lives in
`config/puma.rb` as `DEFAULT_PORT = 3017`, with the same correction in
`config/environments/development.rb` (a generated dev URL pointing at 3000
would open that other app), and `spec/config/port_spec.rb` asserts both.

**The general lesson, which is bigger than the port:** a convention that can
only be honoured by remembering it is not a convention, it is a trap with a
docstring. Put it where the wrong thing is impossible.

Two smaller notes from the same fix: the port question originally looked like a
conflict between 3017 and 3028 and was not — 3017 is this API and 3028 is
Metro, the mobile bundler, two services that never needed to agree. And the
first version of `port_spec.rb` **failed against a correct file**, because the
comment explaining the old `ENV.fetch("PORT", 3000)` was matched instead of the
code. A checker that reads prose is measuring the wrong thing whichever way it
lands; it strips comments now.

### A jest setup file can hollow out a test — recorded for the mobile repo

Not an API problem, but the same class as everything else in this file and the
mobile repo's `src/__tests__/setup.ts` now carries it in full:

- `setup.ts` imports `@/i18n` **before** any test file's `jest.mock` registers,
  so that module has already bound the real dependency and a later mock of it
  is never called. A test written that way passes for the wrong reason.
- The mocks in a setup file can make a bug **unreachable**: a no-op restart and
  a pre-applied `forceRTL(true)` are exactly the two conditions under which the
  F-01 restart loop cannot occur, which is why 83 green tests missed an app
  that never rendered on a device.

Mock the LEAF the device actually uses, and assert both directions of any rule.

### Found by the FIRST DEVICE RUNS — and the app had never rendered at all

The mobile app met an Android runtime for the first time on 2026-09-15. It did
not boot. Two runs produced twenty findings; what follows is the ones with a
lesson beyond their own fix. Full detail in `karwan-mobile/qa/UI_FINDINGS.md`.

**F-01 — the app restart-looped forever and rendered nothing.** 55 root mounts
in 20 seconds, a blank grey screen, and Pashto and Dari — two of three locales
and the entire target market — unreachable. The premise was false:
`RNRestart.restart()` recreates the JS context in the SAME process, so the
native RTL flag does not come back changed, so "the flag disagrees" stayed true
on every mount. **83 green tests, `tsc` and `eslint` all passed over an app
that never rendered.**

**F-19 — the app went HALF-MIRRORED, and the test could not have caught it.**
`setLanguage` restarted only when the language STRING changed, and that is
false for the commonest first interaction in the app: a fresh install tapping
پښتو, which is already the current language because `lng: DEFAULT_LANG`
initialises to it. `forceRTL` DOES move `isRTL` within the running context, so
everything mounted afterwards laid out RTL and everything already on screen did
not.

> **One platform, two scopes.** `forceRTL` never moves `isRTL` ACROSS a
> restart, and always moves it WITHIN a context. The test harness modelled only
> the first, so it could not have caught the second no matter how many examples
> it grew. When a platform behaviour differs by scope, the harness needs both
> or it is asserting one of them twice.

**F-15 — every role-scoped endpoint was 401**, because there is no login screen
yet, so the only surface the app could reach was the public merchant list. That
single fact capped four findings at once. Closed by `db/seeds/e2e.rb`, which
the rig drives by signing in the way a person does — phone, OTP, in.

**F-02/F-20 — the support number.** It shipped as a placeholder that rang
nobody, then as a build-time constant no admin could change, then as a blank
server value that silently overrode a correctly configured build. Now one
`Setting` row, served publicly, with the build value as the fallback for when
the server cannot be reached — which is exactly when somebody wants to ring.

**R-12 — the rig was WRITING into Hatiwal's live database.** `clear_blocks.sh`
defaulted to a container that is up on this box, once per feature.

> **A copied rig carries its origin's assumptions, and they escalate.** Wrong
> port, then wrong application, then wrong question, then wrong database. The
> read-only ones cost a false verdict; the WRITE ones cost somebody else their
> data. Audit the writes first.

### Small gaps the mobile wiring exposed and did not close

- **The active order costs two requests.** There is no `/customer/orders/active`.
  The LIST is the only thing that says which order is live (`is_live`), and the
  DETAIL is the only thing carrying the timeline and the courier's phone. The
  app fetches both. Cheap enough (two tiny responses on a screen the customer
  lives on) that a third shape of the same record is not yet worth the drift
  risk. **Trigger:** if the status screen ever feels slow on a real Kabul
  connection, collapse it.
- **`Customers::QuoteSerializer#suggested_notes` returns the total unchanged.**
  So "have change for 500" is computed on the device
  (`src/lib/orderStatus.ts`: round up to the next 500, stay quiet on a multiple
  of 100). That is a presentation rule and it is tested, but the rule belongs
  here once Hamma9900 settles it — he knows which notes people actually carry.
  The old hardcoded copy advised "change for 500" on a 1,250 AFN order.
- **`Couriers::JobSteps` sends `completed` but no timestamp per step.** The
  courier's stepper therefore shows ticks and no times, while the customer's —
  built from the transition log — shows both. Correct for a man being told what
  to do next; add `at` if he ever needs to prove when he paid.
- **A `ready` order has nothing to say to the merchant.** No merchant action
  exists (the COURIER records the handover, which is the right side of the
  transaction to trust), so the card carries no button and no copy. It needs a
  Pashto string meaning "waiting for the courier" — Hamma9900's.

### Closed on 2026-09-15/16 — listed so nobody re-opens them

- **A courier could not be created at all.** No application endpoint, and the
  admin console had no `new`/`create` — an index over a table nothing could
  write to. `POST /api/v1/courier/registration` now takes a partial
  application and reports what is still owed as field names.
- **Approval granted two things of three.** Status and wallet, never the
  `courier` ROLE — so an approved courier saw no jobs (`CourierScope` resolves
  to `none`) and could not switch into the courier tab. One transaction now.
- **The approver could not be recorded.** `verified_by` points at `users` and
  the console operator is an `AdminUser`, so it could only ever be nil, against
  CLAUDE.md's "a nil approver is not a valid state". `verified_by_admin_user`
  added to courier_profiles AND merchants.
- **Nothing could upload a file.** Eight `has_one_attached` macros, no endpoint
  and no admin field — every gate green because the macro never touches the
  database. Catalog photos, address voice notes and courier documents now
  upload; `AttachmentField` lets an operator SEE the tazkira they approve.
- **The OTP SMS did not exist** — a code was logged and no message was ever
  composed, on the first thing anybody in Kabul reads from this platform.
- **The API defaulted to port 3000**, which is another live application here.
- **The merchant board dead-ended at `accepted`**, and its cards carried no
  money.
- **`OrderPolicy#track?` was written, correct, and called by nothing.**

### Map tiles stop at the Afghan border, but the app does not
`hatiwal-map` builds its tileset from `afghanistan-latest.osm.pbf`, so anyone
just over the border gets blank tiles. The app itself has no country
restriction and is deliberately usable on a Pakistani or Iranian number
(R13) — so the map is the one place where "for Afghanistan" is enforced in
infrastructure rather than by choice.

Not a v0 problem: the first neighbourhood is in Kabul. Worth knowing before
anyone reports "the map is broken" from Peshawar. Fixing it means a wider
`--bounds` in planetiler AND the matching `bounds` in `build-styles.mjs` — the
runbook is explicit that a mismatch makes MapLibre request tiles that do not
exist.

### Closed as a result

**`RateLimitable`** — hatiwal-api had it and we had nothing except the
per-phone OTP throttle. Adapted with its reasoning, which is the valuable part:
fails OPEN so a cache outage cannot turn sign-in into a 500, uses a real
MemoryStore in tests because `:null_store`'s increment returns nil and would
make every limit a silent no-op, and keeps **IP limits generous because Afghan
mobile users sit behind carrier-grade NAT** — a whole neighbourhood can share
one address, so a limit tight enough to be interesting locks out a real street.

### Deliberate differences, not gaps

| hatiwal-api has | Karwan does not, because |
|---|---|
| `devise_token_auth` | Authenticates on an email uid; phone is our identity (correction 2) |
| `faraday`, `signet` | Google sign-in, excluded by instruction |
| `redis` | All three solid adapters run on Postgres |
| `chartkick`, `groupdate` | PRODUCT.md asks for numbers, not charts |
| `postmark-rails` | No email anywhere — the identity is a phone number |
| `app/channels/`, `cable/` | Polling beats WebSockets at our scale, with written switch triggers in docs/REALTIME_AND_SCALE.md |
| `Dockerfile.dev` | The app runs on the host; only Postgres is containerised |
| `app/validators/` | No custom validator needed yet; adding an empty directory is not parity |
| `spec/serializers/` | Serializer keys are asserted in the request specs, which test the real payload rather than the object |

### THE ONE REAL GAP STILL OPEN: no API documentation

hatiwal-api generates OpenAPI from rswag request specs and serves it at
`/api-docs`. We have `rswag-api` and `rswag-ui` in the Gemfile and
**`swagger/` does not exist**, because the request specs are written in plain
RSpec rather than the rswag DSL.

This is a genuine gap and it is deliberately deferred rather than forgotten.
The cost is rewriting ~200 request examples into the rswag DSL; the benefit is
browsable docs. It matters most at the moment a second person writes a client —
and right now the only client is being written in this same session, against
the controllers directly.

**The trigger to do it:** anyone other than this session needs to call the API.
At that point it is worth the rewrite; before it, the specs already document
the endpoints and the rewrite would buy a web page.

## Solved, with the reasoning

### Cross-script search — CLOSED, and the design was chosen by measurement
A customer typing `kabab` could not find کباب. The failure mode was the worst
kind: the app looked **empty rather than broken**, so nobody would report it,
and a customer acquired by a personal conversation would be lost silently.

Two designs were possible — transliterate the QUERY, or store a normalised
column. **Measured first**, against the 0.3 trigram threshold:

| query | consonant skeleton | word_similarity |
|---|---|---|
| kabab | kbab | 0.375 ok |
| kabob | kbab | **0.167 fails** |
| mantu | mntw | **0.167 fails** |
| burger | brgr | **0.143 fails** |
| bolani | bwlany | **0.200 fails** |

So a character map alone does not work: Arabic script omits short vowels and
writes و/ی where Latin writes o/u and i/y. That made the **curated dictionary
the primary mechanism and romanisation the fallback**, rather than the reverse.

**Stored column, not query transliteration**, for three reasons: it works in
BOTH directions from one index (transliterating the query only bridges
Latin→script, so someone typing کباب against "Kabab House" would still find
nothing); query time is unchanged at one GIN index; and script→Latin is
defensible while Latin→script is ambiguous, so romanising once at write time is
the direction that has an answer.

Romanisation emits multiple forms per letter and one inserted-"a" guess, which
is what rescues `kabab` from کباب exactly rather than hoping trigram bridges
`kbab`. Only "a" is inserted — adding "i" and "u" multiplied the variants
without adding matches in the measured cases, and an index of near-duplicates
makes every query slower for nothing.

**A spec caught that the SCRIPT side needs variants too.** The dictionary had
منتو, a merchant wrote مانتو, and `mantoo` found nothing — the Latin spellings
were only reachable through the one script form listed. Both spellings are
real, and a merchant types whichever they use.

`COALESCE(search_text, name)` everywhere, so a row whose column has not been
built yet is still findable rather than invisible.

### Order timeouts — CLOSED by `eadd223`
`Dispatch::ExpireOffersJob` and `Dispatch::JobTimeoutsJob` both exist and are
scheduled in `config/recurring.yml`. Closing that gap also revealed that
**solid_queue had never been installed**, so even a correct schedule would have
run nowhere.

### `Setting` rows are read throughout — CLOSED
`Pricing::DeliveryQuote` and `Pricing::RideQuote` read them on every quote
(3 and 5 call sites), and an admin spec changes a fee through the console and
asserts the NEXT quote is different. The Config screen closes that loop.

### Shamsi dates and Eastern Arabic numerals — CLOSED in karwan-mobile
`src/i18n/shamsi.ts` and `src/i18n/numerals.ts`, both with tests. Verified
before moving this entry rather than taken on trust.


### OTP send throttling — CLOSED, and it was a bill rather than a security gap
`OtpVerification` limited *guesses* (`MAX_ATTEMPTS`) but nothing limited
*sends*. Anyone reaching the request endpoint could bill us for SMS and harass
any number in Afghanistan.

The reframe that raised its priority: SMS is one of exactly **two** recurring
costs in v0 (the other is the VPS), and the owner is self-funding. An
unthrottled endpoint is somebody else spending his money.

Two limits, because they stop different things:
- **burst** — `otp_max_sends_per_window` (3) within `otp_send_window_minutes`
  (15). Stops hammering one number.
- **daily** — `otp_max_sends_per_day` (10). Caps what one number can ever cost,
  however patient the caller. Without it, a sliding burst window is an
  unlimited budget spent three at a time.

Counted from the rows, not from a cache, so it survives a restart and cannot be
reset by making the cache miss. Raised *before* the code is generated, since the
cost being protected is the SMS. `Throttled` carries `retry_after_seconds`,
because "too many attempts" with no number is the dead end that loses a
first-time user — and every user here arrived through a conversation somebody had
in person.

**Proven to fail**: removing the `raise` turns 4 examples red; restoring it
turns them green. Self-review Q1 done rather than claimed.


### `db:migrate` on an EMPTY database loads `schema.rb` and marks every migration applied
This is the worst trap hit so far, because it reports success.

After editing existing migrations, `db:drop db:create db:migrate` printed only
the one NEW migration and `db/schema.rb` still described the old tables. The
database had been rebuilt from the **stale schema.rb**, with every migration
version inserted into `schema_migrations` as though it had run.

I then "verified" by reading `schema.rb` — which is the file the database had
just been built from. Reading the artefact to check the artefact.

**After editing an existing migration, delete `db/schema.rb` before
re-migrating**, and verify against the database:

```bash
rm -f db/schema.rb && bin/rails db:create db:migrate
psql ... -tc "select tablename from pg_tables where schemaname='public'"
```

Self-review Q2 exactly: verify where it lands, not where you are looking.

### `similarity()` compares WHOLE strings — use `word_similarity()`
The fuzzy search fallback returned nothing for the only queries it existed to
catch. `similarity('kebab', 'Kabab House')` is 0.200, because it scores the
query against the entire column value including " House". No threshold that
accepts 0.200 would reject unrelated names.

Measured, rather than reasoned about:

| query | `similarity` | `word_similarity` |
|---|---|---|
| kabab | 0.500 | 1.000 |
| kebab | **0.200** | **0.333** |
| kabob | **0.200** | **0.500** |
| pharmacy | 0.000 | 0.000 |
| pizza | 0.000 | 0.000 |

`word_similarity(query, column)` scores against the best matching extent inside
the column, which is what someone searching a shop name means. Threshold is
**0.3** — under "kebab" at 0.333, far above unrelated at 0. Re-tune by
re-running that query, not by reasoning about trigrams.

Two guesses were wrong before measuring (0.2 with the wrong function, then 0.4
with the right one). **Measure the numbers.**

### `has_one_attached` without Active Storage installed fails silently until first use
Seven `has_one_attached` declarations existed across Merchant, CatalogItem and
CourierProfile, and `active_storage:install` had never been run — no
`active_storage_blobs`, no attachments table.

Nothing caught it. `ruby -c` passes, `rubocop` passes, `zeitwerk:check` passes
(the macro does not touch the database at class-definition time), and 103 specs
passed because none of them attached a file. It would have failed on the first
photo upload, in the feature that matters most in this market.

**If a model declares an attachment, assert that attaching one works.** A macro
that needs a table is not verified by a suite that never exercises it.

### Inside a `scope` lambda, `self` is the RELATION, not the class
`scope :live, -> { where.not(status: self::STATUSES.values_at(*TERMINAL)) }` in a
concern raises `TypeError` — an `ActiveRecord::Relation` is not a Module, so
`::` cannot resolve a constant through it. Reach class constants through a class
method instead, which the relation delegates to `klass`.

### A sed-based rename mangles prose, and a shoulda matcher can assert the unreachable
Two small things from the merchant rename worth knowing:

- Renaming `restaurant` to `merchant` across 39 files rewrote carefully-worded
  comments into slightly wrong ones. Identifier renames are mechanical; the
  prose around them is not. **Re-read the comments in the files that matter
  after a bulk rename.**
- `it { is_expected.to validate_presence_of(:top_up_code) }` failed because a
  `before_validation` callback assigns the code, so it can never be blank. The
  matcher was asserting a state the model cannot reach — a check that cannot
  fail, in the opposite direction. Removed in favour of testing the behaviour
  that exists.


### `Order::TRANSITIONS` named a role that does not exist — and one spec passed anyway
The table said `:merchant`. The role is `:merchant_owner`. So
`can_transition_to?(:accepted, actor_role: :merchant_owner)` returned false
for every merchant transition: **the merchant could not accept its own
orders**, and nothing raised, because a missing key in that table is
indistinguishable from a forbidden transition.

The part worth remembering is the second half. The example
*"does not let the customer accept their own order"* **passed** — vacuously,
because no role matched at all, so the negative assertion was true for the wrong
reason. A suite of per-cell examples would have shown one red and several
misleading greens.

Fixed by checking the whole table instead of sampling it: two specs assert that
every role and every status named anywhere in `TRANSITIONS` is a real one.
Proven to fail by planting the original bug back:

```
TRANSITIONS names roles that do not exist: [:merchant]
1 example, 1 failure
```

**Lesson: when a lookup table's keys are strings or symbols that must match an
enum, assert the whole table against the enum.** A negative assertion that
passes because the key is absent is the worst kind of green.

### A `bin/rails runner` in RAILS_ENV=test leaves rows behind, and the failure blames your factory
Linting the factories through `bin/rails runner` (not transactional) left users
in the test database. The next `rspec` run restarted its sequences at 1, hit
those rows, and reported:

```
ActiveRecord::RecordInvalid: Validation failed: Phone has already been taken
  # ./spec/factories/orders.rb:7
```

which points at the factory. The factory was fine. Fixed properly with
`DatabaseCleaner.clean_with(:truncation)` in a `before(:suite)` hook — per-example
transactions isolate examples from each other but do nothing about rows that were
already there when the suite started.

Same class of problem as hatiwal's "Two sessions, one database — fixture state is
shared, and it bites". **If a unique-column collision surfaces from inside a
factory, check what is already in the database before reading the factory.**


### `has_many` takes its scope BEFORE the options hash
`has_many :options, class_name: X, -> { order(:position) }, dependent: :destroy`
is a syntax error — Ruby sees a lambda where a hash value should be:

```
unexpected ','; expected a value in the hash literal
```

Correct: `has_many :options, -> { order(:position) }, class_name: X, dependent: :destroy`.
Cost two files. Caught by `ruby -c` on every model after writing, which is now
the habit rather than waiting for a boot.

### `ruby -c` is not `zeitwerk:check`
Every model parsed and two of them still would not have loaded. The house
convention `class_name: Model.name` (hatiwal-api's CLAUDE.md: never a string)
evaluates the constant at class-definition time, so `User` → `Merchant` →
`User` is a real load-order cycle. It resolves — Ruby hands back the
partially-defined class and `.name` works on it — but the only way to know is
`bin/rails zeitwerk:check`, which eager-loads everything.

**Run `bin/rails zeitwerk:check` after adding models.** "Syntax OK" is a claim
about the parser, not about the app. (Self-review Q2: verify where it lands.)

### The test database URL must be derived, not declared
`config/database.yml` builds the test URL by parsing `DATABASE_URL` and swapping
the path, instead of using a `database:` key. `DATABASE_URL` takes precedence
over `database:`, so the natural-looking config runs the suite against — and
wipes — the development database. Copied from hatiwal-api, where the comment
records it having actually happened.

### Soft delete is NOT a `default_scope`
`SoftDeletable` gives you `kept` / `discarded` scopes and nothing automatic. A
`default_scope` leaks into every join, association and `count`, and the escape
hatch (`unscoped`) discards the rest of the query with it — so the first person
who needs a discarded row writes `unscoped` and silently drops a `policy_scope`
too. That failure is invisible. Forgetting `kept` shows deleted rows, which is a
visible bug. Prefer the visible failure.

### 23 tables, not 22
The schema commit message said 22. Counted: 23. Amended before pushing. Worth
noting only because it is the same class of error as everything else in this
file — a number stated from memory instead of from the output.

---

## Inherited traps — from Hatiwal, edu-safi and multi_magic

These have not bitten *this* repo yet. They will.

### A check that cannot fail is worse than no check
Five separate instances in one day across the other repos: four vacuously-green
suites, a structural checker blind to its own blind spot, a lint gate that
inspected only `spec/`, another with 726 disabled cops, and a lint run that
passed because it skipped a whole cop family. **Prove every gate can go red by
planting the bug it should catch.** A green suite that runs zero examples is the
most expensive artefact in software.

### A typed HTTP response is a cast, not a validation
`http.get<T>()` asserts the shape; it does not check it. The interface agrees
with itself while being wrong. multi_magic shipped a screen that blanked on
first use with green request specs and green `tsc`, because nothing rendered the
component. Relevant here as: **a request spec asserting a serializer's keys does
not prove the app reads them.** Mobile check in the same pass.

### Never sum across currencies
edu-safi shipped a total that added afghanis to dollars. Hence `Monetary` and
`WalletEntry.totals_by_currency`, which groups. v0 is AFN-only, which is
precisely when this is cheap to get right.

### Android modals hide toasts
`sonner-native` wraps its Toaster in `FullWindowOverlay` on iOS but not on
Android, where a `<Modal>` is its own native window and covers it. An error
toast fired while a sheet is open is **invisible on Android and fine on iOS**.
This app will be full of sheets. Render errors **inline**, and gate any
Android-only fix on `Platform.OS`. For the API side this means: an error payload
the app cannot display is not a handled failure path.

### i18n traps that will hit the three locales
A plural-only key with no base form renders the raw key on screen. Pass the
**number** for plural selection and the **formatted value** separately. Add keys
to all three locales or parity checks lie. For RTL use **logical** spacing
utilities, and mirror directional icons — a correct `dir` with a left-pointing
"next" arrow is still wrong. Pashto and Dari strings run longer than English.

### TWO METHODS THAT LOOKED LIKE THE ROLE GATE, WITH NO CALLERS — DELETED
`Authenticatable#current_role` and `Authenticatable#require_role!`. The first
carried a comment explaining that the role is never taken from the client
because four roles in one app is where privilege escalation gets forgotten. The
second rendered a 403. **Neither had a single caller.**

Dead code that looks like a guard is worse than no guard, because it stops the
next person looking for the real one — and invites them to build authorisation
on it.

**What actually enforces role access, established rather than assumed:**

1. `ApplicationPolicy#courier?` / `#merchant_owner?` / `#admin?` / `#customer?`
   read `user.role?(...)`, and the policy SCOPES return `.none` without the
   role. The scopes are the half that leaks quietly: a missing predicate is a
   403 somebody notices, a missing scope is another courier's jobs on screen.
2. `Api::V1::BaseController` runs `verify_authorized` and
   `verify_policy_scoped` as after_actions, so a controller that forgets Pundit
   raises on the way out. Every `skip_authorization` in the app was checked
   individually: all of them are on not-found paths that return no data, and the
   two `skip_policy_scope` calls are on records resolved from `current_user`
   and authorised explicitly.
3. The role namespaces add CAPABILITY on top: `Couriers::BaseController`
   requires an approved profile and a wallet; `Merchants::BaseController`
   requires ownership.

Also checked, because it was the obvious way for the two to disagree:
`CourierProfileDashboard::FORM_ATTRIBUTES` does **not** include
`verification_status`, so an admin cannot approve by form and bypass
`approve!`, which grants the role. No split brain.

**Deleted rather than wired in, and the reason matters:** `active_role` is
which TAB a device is showing. Gating capability on it would break the
two-phone setup IDENTITY_AND_ROLES.md §6 requires — a courier whose phone is in
the customer tab must still be able to work the job he is carrying. That is now
an explicit example, so the obvious-looking "fix" fails a test.

### THE THIRD INSTANCE: COVERAGE OF A RULE IS NOT COVERAGE OF WHAT ENFORCES IT
Three in this project now, and they are the same mistake wearing different
clothes:

| | The test claimed | What it actually touched |
|---|---|---|
| dispatch race | one live job per courier | the check at OFFER time — 15 of 16 examples passed with the accept-time re-check deleted |
| i18n boot | the language switch survives a restart | only the across-restart scope, so a half-mirrored app shipped |
| `current_role` | the role never comes from the client | an outcome produced by other code entirely; the method had no callers |

And a fourth, which is a different failure from the three above — not a check
that cannot go red, but a **fixture describing a world the rules forbid**:

| | The fixture claimed | What the rules allow |
|---|---|---|
| user factory | a courier holding `courier` and not `customer` | impossible: `grant_role!` always grants both |

**A suite built on impossible data does not only miss bugs — it manufactures
them.** This one presented as a bug in correct code: the session-issuing logic
was right, the test failed, and the failure pointed at the code rather than at
its fixture. Somebody spends that debugging time, and it is whoever is unlucky.

**Fixtures must go through the same code that creates production records.**
`grant_role!` is the invariant's home, so a factory writing `user_roles` rows
directly is asserting against a different system.

Four questions, then, and each catches a different one:

- **Can the check go red?** — plant the bug.
- **Is the code under test reachable at all?** — if a plant changes nothing
  anywhere, either the code is dead or the test is about something else, and the
  second is worse, because the comment then misdescribes what is protected.
- **Does the test observe the state it is asserting about?** — the i18n boot
  test modelled one scope of two.
- **Could the database state this test sets up ever occur through the app?**

### A FACTORY CAN BUILD A USER THE APP CAN NO LONGER PRODUCE
The `:courier`, `:merchant_owner` and `:admin` traits wrote `user_roles` rows
directly, so a factory courier held `courier` and NOT `customer` — a state
Hamma9900's rule now forbids and `User#grant_role!` prevents. It surfaced as a
test that looked like a bug in the code: issuing a session in the customer tab
for a courier fell back to the courier tab, correctly, because that courier
genuinely did not hold the customer role.

Traits go through `grant_role!` now. One existing example changed meaning as a
result and it is worth reading twice: `OrderPolicy#create?` refused a courier
before and allows one now. **A courier and a restaurant owner may buy food** —
the same human delivers a meal at 13:00 and buys one at 20:00, and a policy
that refused him would have made the platform's own couriers the only customers
who cannot order.

### A SHOP'S APPLICATION IS A `merchants` ROW, NOT A LEADS TABLE
The "sign in as a restaurant" door writes a `merchants` row in a new `lead`
state. I had built a `merchant_leads` table first; Hamma9901 was right that it
was the wrong shape, and the reasoning is worth keeping: `merchants` already
carries `owner_phone`, `owner_name` and a verification status, the console
already has a merchants index Hamma9900 watches, and a lead genuinely IS a
merchant awaiting verification. So onboarding is **continuous** — he calls
them, finishes the same row, assigns the owner, and `sync_owner_role` grants
the role — with no second dashboard and no schema change beyond one enum value.

What made it safe to put an unvetted row in that table:

- **`MerchantPolicy::Scope` is `kept.status_active`**, so a lead is invisible to
  browsing and unorderable. Asserted rather than assumed.
- **The form sets no `owner_id`.** Assigning an owner grants the role and
  `Merchants::BaseController` resolves the board from `owner_id` alone, so
  setting it would hand a merchant board to anyone who typed a shop name into a
  form. The applicant's phone goes in `owner_phone`, which is how he finds their
  account — the phone IS the identity.
- **`require_merchant!` refuses a `lead` outright**, because he may well assign
  an owner while on the phone to a shop that is still a lead. `pending` still
  passes: a merchant being onboarded builds their menu before going live.
- **Strong params drop everything else.** A form that could set its own
  `commission_rate` would be the most expensive input field in the app.

### CONSOLE FORM SAVES WERE NOT AUDITED AT ALL
`log_intervention` was called by hand from the custom actions, so approve,
suspend, reassign and credit were audited and Administrate's own
create/update/destroy were not. That covered the buttons and missed the form —
where the two most consequential edits in the system live: `commission_rate`
changes what a merchant is paid and `owner_id` changes who controls a
restaurant, and both are a plain save.

Hooked on `Admin::ApplicationController` so every dashboard inherits it,
including ones added later. `create` uses Administrate's own block (it keeps
the record in a local), `update` reads `previous_changes`, which is already the
before/after this table stores, and `destroy` snapshots the row first — that
one matters most, because afterwards the audit log is the only place those
values still exist. Nothing is written when nothing changed or when the save
was refused, and `search_text` is excluded or it would dominate every row.

`Admin::SettingsController` keeps its own `setting.changed` line, which is
better than a generic edit because it names the key — "why did the delivery fee
change last Tuesday" is a question about a key, not a row id.

### A TEST CAN BE ABOUT THE OUTCOME AND NOT ABOUT THE CODE
`docs/IDENTITY_AND_ROLES.md` §9.2 requires that `current_role` never takes a
client-supplied role. Three endpoint examples asserting exactly that stayed
**green** when I rewrote `current_role` to read `params[:role]` and an `X-Role`
header first.

The reason: **`current_role` has no callers.** The role namespaces and the
Pundit scopes read `user_roles` directly, so the method is a contract waiting
for its first consumer — the kind of not-quite-dead code somebody uses in six
months assuming it was tested.

It is now tested at the method, by a probe that includes the concern and
defines **neither `params` nor `request`**, so any implementation reaching for
the request raises. The rule is not "prefer the session" — it is "the request
is not an input to this question".

### Vehicles: `rishka` and `zarang` exist, and nothing knows how big a delivery is
Added as new integers 4 and 5 (never renumber — the values are in the
database). `zarang` is a rishka built for heavy goods; Hamma9900's example is a
bed, and it carries more furniture than a car does, so **capacity is not a
ladder from bicycle to car**.

**The gap that is still open: nothing expresses how big a delivery is.**
`orders` has no size or weight and neither does `catalog_items`, so a bed and a
book are indistinguishable to dispatch, and a bed-sized delivery can be offered
to a courier on a bicycle — who accepts in good faith, arrives, and cannot
carry it. That failure costs the customer, the merchant and the courier at
once. Proposed shape (with Hamma9901, not built): a size class on
`catalog_items` defaulting to smallest, the order's requirement being the
maximum over its items and **snapshotted onto the order** like the prices, an
ordered capacity per vehicle class taken from Hamma9900 rather than guessed,
and one more `Dispatch::Eligibility` check — `:vehicle_too_small`, needing no
new query once the requirement is on the row.

Dormant until a store with beds signs up: the first ten merchants are
restaurants and food is always small.

### NOTHING GRANTED THE MERCHANT ROLE — CLOSED, and it would have hit the first restaurant
`merchants.owner_id` is set through the console's generic form, and setting it
granted nothing. `:merchant_owner` existed in `db/seeds/sample.rb` and
`db/seeds/e2e.rb` and **nowhere in `app/`**. So the launch-day sequence was:
Hamma9900 sits with a restaurant owner, onboards them, sets the owner to their
phone — and that person signs in and cannot reach the merchant tab.

Worse than a clean failure, because `OrderPolicy::MerchantScope` keys on
`merchants.owner_id` and resolves without the role, while the role-gated
endpoints refuse. Half the surface works, so the symptom points at the app
rather than at a missing `user_roles` row.

**The same bug courier approval had** — status set, wallet created, role never
granted — on the path he uses FIRST, because merchants are admin-onboarded and
couriers self-apply. That pattern is now explicit enough to check for directly:
*when a record makes someone a partner, does anything create the role row?*

Closed with `after_save :sync_owner_role` on `Merchant`. **On the model, not in
the controller**, because the owner can be set from the Administrate form, a
seed, a console or any admin path added later, and a callback is the only place
that catches all of them. It also handles the reverse, which is the same bug
backwards: a former owner keeping merchant access to a restaurant that is no
longer theirs. Revocation is skipped while they still own another kept
merchant, because one person holding two shops is not hypothetical on a launch
where shops are signed one at a time.

### Partner → customer is automatic; customer → partner never is
Hamma9900's rule: *"the client account open if we have restaurant or rider or
driver account automatic, because it's not a big thing"*, and *"when we create
client, we can't give access to create account as rider etc."*

The first half held only by accident of the path — `SignInService` creates
every account with `:customer`, so anyone who arrived through the app had it,
while a courier created by a seed or by the console did not. It is a rule now:
`User#grant_role!` always grants `:customer` alongside, and `revoke_role!`
never takes it away. A courier who cannot order food breaks the premise the
shared pool rests on — the same human delivers a meal at 13:00 and buys one at
20:00.

The second half was already true and stays that way: `switch_role!` refuses a
role the user does not hold, and the role is derived from `user_roles`, never
from the client.

### A GUARD WITH NO CALLER IS NOT TESTED BY ITS NEIGHBOURS
`revoke_role!` refuses to remove `customer`. Deleting that guard left all
25 merchant-ownership examples green, because nothing in the app revokes
`customer` — the neighbouring tests pass for a different reason than the one
their comments claimed. The guard needed a direct example in
`spec/models/user_spec.rb` calling `revoke_role!(:customer)`.

Sharpens the standing rule: **planting the bug has to make the specific test
red, not merely some test.** A plant that changes nothing anywhere means either
the code is dead or the test is about something else — and the second is worse,
because the comment then misdescribes what is being protected.

### `admin` was offered as a role on the phone
The role switcher reads `user.roles`, which was every `user_roles` row — so a
user holding `:admin` was offered an admin tab that does not exist (correction
16: there is no admin surface in the mobile app, and nothing that can credit a
wallet belongs on a device that gets shared or lost). `Roles::MOBILE` now
excludes it, the serializer intersects against it, and both `switch_role!` and
the sign-in role request refuse it even for a genuine admin.

### The role is chosen at the door
`POST /api/v1/auth/session` takes an optional `role`. Absent means customer,
which is never asked — "sign in as partner" is the quieter second action that
sends one. A refused role does **not** fail the request: the code has already
been consumed, and failing would cost a second SMS (the only real per-unit cost
in v0) and strand exactly the person we most want — someone signing in as a
courier who has not applied yet. The refusal rides along as
`role_request: { requested, granted: false, code }`, with two distinct codes
because they need two different screens: `role_not_held` leads to an
application, `not_a_mobile_role` has nothing to apply for.

### One account had one mode everywhere — CLOSED by moving it to the session
`users.active_role` decided which tab the app opens in, which made it a fact
about a PERSON. It is a fact about a DEVICE: a merchant keeps a tablet on the
counter and a phone in his pocket, and a courier whose phone dies mid-shift
signs in on a second one without signing out of the first. Flipping the phone
to the customer tab flipped the tablet's next launch too.

Now `user_sessions.active_role` holds the live mode — the same scope
`Authenticatable` already resolves per request, so it costs no extra query —
and `switch_role!` moved to `UserSession`.

**The column on `users` was NOT dropped; it was renamed `last_active_role`,
because it was doing a second job that is still wanted.** `MeController` says
why in its own comment: a reinstall must not drop a courier back into the
customer tab, and a reinstall is a NEW session. So there are two columns with
two meanings — `users.last_active_role` is a PREFERENCE that seeds the next new
session, `user_sessions.active_role` is the FACT of what a device is showing —
and the seeding is checked against the roles the person still holds, so a
courier whose approval was revoked is not seeded back into a tab with no jobs
in it.

`switch_role!` also stopped using `update`. Returning false covered both "you
do not hold that role" and "the write failed", so a failed save was reported to
the user as a permissions problem. It is `update!` now, inside a transaction
with the preference write, and `false` means exactly one thing.

Worth knowing: `current_role` had **no other callers** — the role namespaces
and Pundit scopes never consulted it — so this was a UI-mode fact throughout,
not an authorization one. That is also why the fix was cheap.

### FIVE OPS CONSOLE PAGES RETURNED 500 AND 1,078 EXAMPLES WERE GREEN
Found while renaming `active_role`: `UserDashboard` named the column, and
nothing in the suite rendered an Administrate page, so `/admin/users` would
have died on Hamma9900's first click. Adding `spec/requests/admin/dashboards_spec.rb`
— which walks every dashboard's index, show and edit — immediately found that
**five pages were already broken before the rename**:

| Page | Why |
|---|---|
| `/admin/orders/:id` | no `OrderItemDashboard` |
| `/admin/trips/:id` | no `StatusTransitionDashboard` |
| `/admin/merchants` (index and show) | no `MerchantKindDashboard` |
| `/admin/users/:id` | no `UserRoleDashboard` |
| `/admin/merchants/:id/edit` | route did not exist — see below |

Administrate resolves an associated dashboard **by class name at render time**,
so a `Field::HasMany` or `Field::BelongsTo` pointing at a model with no
dashboard is not a boot error, not a model failure and not a request-spec
failure — it is a `NameError` inside an ERB template, on that page only. Eight
dashboards were missing (`Address`, `CatalogCategory`, `CatalogItem`,
`MerchantKind`, `Offer`, `OrderItem`, `OrderItemOption`, `StatusTransition`,
`UserRole`); they are display-only, `FORM_ATTRIBUTES = []`, because a snapshot
or a history that can be hand-edited is neither.

**This is the "verify at the layer where it lands" trap in its purest form.**
The console is the one surface in this project with no second mechanism behind
it: correction 16 says there is no web app, so when an ops page 500s there is
nowhere else for the person in Kabul to go.

### `config.api_only` makes a bare `resources` silently omit `new` and `edit`
`resources :merchants` in the admin namespace generated index, create, show,
update and destroy — **no `new`, no `edit`** — because an API has no forms.
Administrate is all forms, so the "Edit" button on the merchant page pointed at
a route that did not exist, and a merchant's commission rate could not be
changed without a deploy. Every other admin resource happened to spell out its
actions with `only:`, so merchants was the only casualty.

The fix is to spell out `only:` even when you want the default set — in an
`api_only` app there IS no default set for a browser. Nothing warns: the route
is simply absent, the link still renders, and the failure is a 404 on a page
that looks like it should exist.

### A courier could hold a delivery and a ride at the same time — CLOSED
`Dispatch::Eligibility` had nine checks and none of them asked whether the
courier was already carrying a job. So a courier riding to a customer with a
meal in his box could be offered a **trip** and accept it, and nothing refused
him. One human, two jobs, two places, and one of those customers loses for
certain — cold food while he drives a passenger across Kabul, or a passenger at
a kerb while he finishes the delivery. On the launch neighbourhood, with the
pool small, that is the first thing a courier would discover.

Closed with `:already_on_a_job`, placed above the wallet checks (cheapest query,
commonest reason to skip a courier on a busy evening) and spanning **both**
tables — `Order` and `Trip` — because the utilisation thesis is one pool serving
two demand streams, so "already busy" is only true if you look at both. The job
being offered is excluded from the check, so an admin re-offering work a courier
already holds is not refused as a conflict with itself.

**Two checks, not one, and the second is the one nobody would have written.**
Eligibility runs when an offer is MADE, so a courier holding a minute-old offer
can take other work and then accept it. The accept path therefore re-checks
inside `current_user.lock!` and rolls back. Measured: with the in-transaction
re-check deleted and everything else intact, **15 of the 16 new examples still
passed** — only the race example saw it. That is the shape of the bug this
codebase keeps producing, so it is worth stating plainly: *a guard placed at the
moment of decision does not protect the moment of commitment.*

It also settles a question that was going to be asked about phones: **guard the
job, not the device.** Once one-live-job holds server-side, how many phones a
courier carries stops mattering — and it has to stop mattering, because swapping
to a second phone when the first one dies mid-shift is a real thing on a cheap
Android in Kabul.

### `current_organization` is tenancy, not permission
edu-safi had five endpoints where the correct scope existed, was correct, and was
never consulted. Write the scope **and use it**, and add a request spec proving
both the refusal and the legitimate path. The analogue here is
`merchant_id` — belonging to a merchant is not permission to act on it.
