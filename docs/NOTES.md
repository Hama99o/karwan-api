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

### `Setting` rows are not read by anything yet
`Setting.fetch` works and raises on unknown keys, but no order-pricing code
calls it, because there is no order-pricing code yet. When that lands, the
commission/fee values must come from `Setting.fetch`, not from
`Restaurant#commission_rate` alone and never from a constant.

---

## Solved, with the reasoning

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
evaluates the constant at class-definition time, so `User` → `Restaurant` →
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
`restaurant_id` — belonging to a restaurant is not permission to act on it.
