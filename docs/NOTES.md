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

### OTP send throttling is not built
`OtpVerification` limits *guesses* (`MAX_ATTEMPTS`) but nothing limits *sends*.
As it stands, whoever gets the request endpoint can bill us for SMS and harass
any phone number in Afghanistan. Needs a per-phone send limit
(e.g. 3 per 15 min, 10 per day) before the endpoint exists — not after.

hatiwal-api has `app/controllers/concerns/rate_limitable.rb`; read it before
writing a second one.

### Order timeouts are declared but nothing fires them
`Order::TIMEOUTS` gives every non-terminal state a deadline and `Order#overdue?`
reads it, but no job enforces one. **Right now an order can sit in `placed`
forever** — the exact "person waiting with cold food" the brief warns about.
Needs a recurring solid_queue job. Until it exists, the admin board's staleness
colouring is the only thing catching it, which means it depends on someone
watching.

### Search cannot bridge scripts, and the user will read that as an empty app
`MerchantCategory.search` checks all three locale columns, so `کباب` finds a
category. But a merchant NAME or an item name stored in Latin is unreachable by
a Dari query and vice versa, and trigram similarity cannot help — `کباب` and
`kabab` share no trigrams at all.

`docs/AFGHAN_UX.md` is explicit that people type both. The consequence is not a
poor result, it is **zero** results, and a user concludes the app is empty.

Needs a transliteration map or a normalised search column holding both forms.
Not built.

### Shamsi dates and Eastern Arabic numerals are not implemented
Afghanistan does not run on the Gregorian calendar. Store UTC, **render Shamsi**
in Dari and Pashto. Digits render as ۰۱۲۳۴۵۶۷۸۹ per locale, with two exceptions
that stay Latin and left-to-right inside RTL text: **phone numbers and order
reference codes** — mirroring those makes them unusable.

Both belong in the localisation layer, solved once, not per screen. Nothing in
the API formats dates or numbers for display yet, which is the right time to
decide that the API sends ISO-8601 UTC and raw numbers, and the client renders.

### `Setting` rows are not read by anything yet
`Setting.fetch` works and raises on unknown keys, but no order-pricing code
calls it, because there is no order-pricing code yet. When that lands, the
commission/fee values must come from `Setting.fetch`, not from
`Merchant#commission_rate` alone and never from a constant.

---

## Solved, with the reasoning

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
