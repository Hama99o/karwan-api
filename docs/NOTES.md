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

### `current_organization` is tenancy, not permission
edu-safi had five endpoints where the correct scope existed, was correct, and was
never consulted. Write the scope **and use it**, and add a request spec proving
both the refusal and the legitimate path. The analogue here is
`merchant_id` — belonging to a merchant is not permission to act on it.
