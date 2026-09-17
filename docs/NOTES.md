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

> **Re-derived against the code on 2026-09-17**, line by line, rather than
> remembered. The stamp before this one read *2026-09-16, 01:00* and the list
> had drifted by thirty commits: it pointed a reader at a decision Hamma9900 had
> already made, it quoted a number that was never the number, and it left a
> **second gateway** unlisted. **Every entry below names the commit or the file
> that settles it**, because a list written from memory is exactly how that
> happened and a fresher memory is not the fix.
>
> A gap that could not be verified either way stays, marked **unverified**,
> with what would settle it. Deleting an item because nobody could confirm it
> is how a real gap disappears.

### WHAT IS OPEN IS HAMMA9900'S — EXCEPT ONE LINE OF OURS

The backend is functionally complete for v0: **1,523 examples, 0 failures**, as
recorded by `5d86ce8` — that is the last measured count, not a run made for
this rewrite, and the box was too loaded to re-run it honestly.

| Open | What it needs | Where it stands in the code |
|---|---|---|
| **SMS gateway** | His choice and his money | The one true per-unit cost in v0. The seam and the message exist — `Notifications::SmsClient` picks an adapter from `SMS_PROVIDER`, which defaults to `log` and writes codes to the log; `bin/preflight:130` warns that nobody can sign in that way. Choosing a gateway is an afternoon. |
| **SMTP credentials — the SECOND gateway, and this list did not have it** | A host, a user and a password | `config/environments/production.rb:75` sets `delivery_method = :smtp` with every value from ENV and `SMTP_ADDRESS` **defaulting to `localhost`**. It is reached whenever somebody types an EMAIL into the reset form — `Users::PasswordResetService.deliver` picks the channel from the shape of the identifier, then `UserMailer#password_reset`. Because it is `deliver_later`, an unset SMTP host does **not** fail the request: the endpoint answers 200, the app says "check your email", and the code dies in a job. `bin/preflight` warns about SMS and says **nothing** about SMTP. |
| **The support phone number** | One row in the admin console | `Setting::DEFINITIONS["support_phone"]` defaults to `""`; `/public/app_config` serves it and every installed app picks it up with no rebuild. Blank today, so the app correctly hides the button. |
| **Eight Pashto and Dari strings — not two** | His words, once | The login changed under this row and nobody updated it. `app/models/setting.rb` now carries **8** keys marked `AWAITING TRANSLATION`: `otp_sms_body_{ps,fa}`, `password_reset_sms_body_{ps,fa}`, `password_reset_email_subject_{ps,fa}` and `password_reset_email_body_{ps,fa}` — the last four exist because `c7c8d21` replaced the OTP login with a password and a reset flow. An SMS has no device to translate it, so the server holds the words; English placeholders ship until he pastes the real text. |
| **New-courier credit line and the guarantor policy** | His numbers | `default_credit_line` is a `Setting` at 500 AFN, chosen as a placeholder. |
| **Renaming the karwan-api GitHub repo** | His account | — |

**The one line of ours in that table is the SMTP warning.** Every other row
waits on him. `bin/preflight` exists precisely so that a stack which is not
ready says so out loud, and it covers the SMS gateway and says nothing about
the mail one — so the failure it was built to prevent is reachable through the
door it does not watch. It is three lines beside the SMS check; it is not done
here because this rewrite is a doc pass and quietly widening it is how a doc
pass becomes something nobody reviewed.

**Closed since the last stamp, and worth naming because the old row misled
twice.** *OSRM distance for pricing* sat here as his decision, and he made it:
`748c135` turned it on, so `Setting::DEFINITIONS["routing_distance_source"]`
now defaults to **`osrm`**. The row also quoted "raises fares ~29%", which was
never true of a fare — 29% was the DISTANCE ratio. Measured over four Kabul
pairs, the **fee** moves +15.3%, +16.3%, +20.2% and **0%** on a short hop,
because the fixed base dilutes it and the minimum absorbs it entirely. A number
quoted from the wrong quantity is worse than no number, because it is the one
he would have decided against.

Two things are deliberately OUT rather than open: **the ride product**
(PRODUCT.md — "do not build the ride product yet") and **merchant
self-service profile editing** (PRODUCT.md — "not self-serve in v0, admin
onboards restaurants"). **Verified 2026-09-17** for the first: `trips` is
routed only inside the ADMIN namespace as `index`/`show`,
`app/controllers/api/v1/customers/` holds `addresses` and `orders` and nothing
else, and the courier's side is complete — so the model, the pricing and the
courier's ride flow exist and a passenger still cannot request one.


### For karwan-mobile, recorded here because it was found from this side

Not ours to fix — `karwan-mobile` belongs to another session — but it is the
same class as everything else in this file and would be lost in a chat log.

- **`src/api/parse.ts`'s `money()` is the repo's Rails-decimal parser and is
  now used for four COORDINATES** (`courier.ts:92`, `orders.ts:199`, twice in
  `addresses.ts`). The name is a misnomer that will eventually stop somebody
  using it where they should. Proposed there: rename to `decimal()`, keep
  `money` as an alias rather than forking it into two names.
- **Rails serialises every `decimal` column as a STRING**, which cost two live
  blockers today: `Customers::AddressSerializer` sends `{"latitude":"34.54"}`
  and the client's coordinate parser rejected it, so `listAddresses()` threw on
  every real response and the cart's saved-place picker had never once worked
  against a real server.

  **The API-side consequence, taken rather than waited for:** the shortage
  multiplier is `decimal(5,3)` and is therefore deliberately **serialised to
  nobody**. It lives on the order row so a complaint about a high fee is
  answerable from the record, and that record is the ops console — a laptop,
  where a string is a string. Adding it to a mobile payload would have been a
  new decimal for a client to parse and a fresh chance to repeat the bug, in
  exchange for a number the customer has no use for: they were quoted a total
  upfront and it was frozen.

**The rule this pair earns, and it generalises past decimals:** a number the
client only ever DISPLAYS should cross the wire as **a formatted string the
server decided**, and a number the client computes with should cross as
something it can compute with — and you must know which one you are sending.
Rails' `decimal` lands in the middle: it looks like a number in the schema and
arrives as a string, so it silently becomes the first while the client was
written for the second. The failure is not the string; it is that nobody chose.
Three consequences we now take as read: money and coordinates are parsed
explicitly on arrival (`src/api/parse.ts`), totals are never summed on the
device, and a value the customer merely reads — a multiplier, a percentage, a
distance — is formatted once, on the server, in the locale the request carried.

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
  risk. **Trigger — REWRITTEN 2026-09-17, because the old one could never
  fire.** It read *"if the status screen ever feels slow on a real Kabul
  connection"*. Nobody on this box has a Kabul connection, and "feels slow" is
  not a thing anyone records, so it was a deferral wearing a trigger's clothes
  — the same family as a check nobody runs. It is now: **when the two calls
  together exceed 1.5s at the 90th percentile on the rig's throttled profile,
  or when a second screen needs the same pair.** Both are numbers somebody on
  this box can read. **Still true on 2026-09-17:** the `customers`
  block in `config/routes.rb` carries `index`, `show`, `create`, `quote`,
  `cancel` and `track`, and no `active`.
- ~~**`Customers::QuoteSerializer#suggested_notes` returns the total
  unchanged.**~~ **CLOSED.** The rule came off the device: `Monetary`
  (`app/models/concerns/monetary.rb`) owns `change_advice` — nil on a round
  hundred, otherwise the next multiple of 500 — and **both** serializers read
  it, `Customers::QuoteSerializer` and `Customers::OrderSerializer`, so the
  cart and the status screen cannot disagree. It also fixes the arithmetic the
  old note complained about: 1,250 AFN now advises 1,500, where a flat "change
  for 500" was simply wrong. Left here rather than deleted because the reason
  is the transferable part — **a money rule on the device is a money rule
  Hamma9900 cannot change.**
- **`Couriers::JobSteps` sends `completed` but no timestamp per step.** The
  courier's stepper therefore shows ticks and no times, while the customer's —
  built from the transition log — shows both. Correct for a man being told what
  to do next; add `at` if he ever needs to prove when he paid. **Still true:**
  `app/services/couriers/job_steps.rb` merges `completed:` into each step and
  no timestamp beside it.
- **A `ready` order has nothing to say to the merchant.** No merchant action
  exists (the COURIER records the handover, which is the right side of the
  transaction to trust), so the card carries no button and no copy. It needs a
  Pashto string meaning "waiting for the courier" — Hamma9900's. **Still
  true:** the merchant's order actions in `config/routes.rb` are `accept`,
  `reject`, `preparing`, `ready` — and nothing after `ready`.

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
| `postmark-rails` | Mail IS sent now — `UserMailer#password_reset` carries a reset code, and `users.email` has existed since `c7c8d21` — but through **plain SMTP** configured in `config/environments/production.rb`, not a keyed third-party API (correction 14). This row used to read "no email anywhere"; that stopped being true when the login changed. |
| `app/channels/`, `cable/` | Polling beats WebSockets at our scale, with written switch triggers in docs/REALTIME_AND_SCALE.md |
| `Dockerfile.dev` | The app runs on the host; only Postgres is containerised |
| `app/validators/` | No custom validator needed yet; adding an empty directory is not parity |
| `spec/serializers/` | Serializer keys are asserted in the request specs, which test the real payload rather than the object |

**Every row re-checked 2026-09-17** against `Gemfile`, `Gemfile.lock` and the
directory listing. All still hold, and one is worth naming because it could
easily have slipped: `Routing::OsrmClient` talks HTTP with **stdlib
`Net::HTTP`**, so adding a router did not quietly add `faraday` back.

### NO API DOCUMENTATION — still open, still deferred on purpose

hatiwal-api generates OpenAPI from rswag request specs and serves it at
`/api-docs`. We have `rswag-api` and `rswag-ui` in the Gemfile and
**`swagger/` does not exist**, because the request specs are written in plain
RSpec rather than the rswag DSL.

This is a genuine gap and it is deliberately deferred rather than forgotten.
The cost is rewriting the request examples into the rswag DSL; the benefit is
browsable docs.

**MEASURED 2026-09-17, because the estimate here was wrong: it is 423
examples, not ~200** — across 20 files, 70 API routes and 25 controllers. A
figure written from memory in a paragraph arguing for deferral is the kind that
gets believed by whoever finally picks the work up, a third of the way in. It
is days rather than hours, and every one of those examples is a working test
that would be rewritten into a less readable form to produce a web page. It matters most at the moment a second person writes a client —
and right now the only client is being written in this same session, against
the controllers directly.

### THE DECISION, taken 2026-09-17: NO OpenAPI DOCUMENT UNTIL THERE IS A CONSUMER

**This is a skip with a condition, not a gap.** A gap gets rediscovered and
re-costed by whoever finds it next; a decision with a trigger gets honoured.

**The trigger:** a consumer outside this repo needs to call the API. At that
point, rswag DSL on the endpoints *they actually call* — not all 423.

**Until then the description already exists and is executable:** the 423
request specs, and `karwan-mobile/src/api/`. Neither can drift, because both
are run. There is no consumer to drift from, either: correction 16 gives two
deliverables, and correction 18's future split produces four apps written by us
against the same namespaces they call today.

**A hand-written `swagger.yaml` with a route-existence drift check was
considered and rejected**, and the reason is worth keeping because it was
nearly built. Such a check pins that every documented path exists in
`routes` — and **pins nothing about request or response SHAPE**, which is the
only part a client consumes. It would certify the cheapest property while the
expensive one drifted freely, and the page would carry the authority of having
been verified. That is a sixth shape of a lying instrument, and building it the
same day the other five were written down would have been a particularly
expensive joke. A second description that can disagree with the first is worse
than no second description.

**The trigger, restated:** anyone other than this session needs to call the API.
At that point it is worth the rewrite; before it, the specs already document
the endpoints and the rewrite would buy a web page.

**Verified 2026-09-17:** `swagger/` still does not exist, and `rswag-api`,
`rswag-ui` and `rswag-specs` are all still in the `Gemfile`. The trigger has
moved closer than the paragraph above admits — the client is written by a
SECOND session now (`karwan-mobile`, Karwan [9d4e65]) rather than by this one —
but it is still one person's two sessions reading the same controllers, so the
deferral holds. **It stops holding the moment somebody who cannot read this
repo needs an endpoint.**

**This heading used to say "the one real gap still open", and that was already
false when it was written** — the SMTP gateway above had no entry anywhere. A
superlative in a gap list is a claim about everything you did NOT write down,
which is the one claim a list like this cannot support.

## Solved, with the reasoning

### `git add -A` SWEPT ANOTHER SESSION'S WORK INTO COMMIT `21dffee`

**`21dffee` is not what its message says.** Titled *"the before-balance two
wallet movements never recorded"*, it also contains `db/seeds/e2e.rb` (+19) and
`spec/seeds/e2e_spec.rb` (+24) — Karwan [9d4e65]'s uncommitted change-note
coverage work, including the `items_total: 405` that makes the seeded live
order 505.

**So `git log db/seeds/e2e.rb` explains that total with a message about wallet
auditing.** Anybody bisecting a seed change to that commit will read the wrong
cause. Recorded rather than rewritten: **history rewriting in a tree another
session is actively working in is worse than a misattributed commit.**

**THE RULE: `git add <named paths>`. Never `-a`, never `.`, while another
session shares this checkout.** It lives here rather than in `CLAUDE.md`
because the brief is Hamma9900's.

**The generalisation, which is the part worth keeping — this is the SECOND
cross-session collision in this repo today.** The first was an unapplied
migration taking the shared development API down for every session. Same root
both times: **an action whose blast radius extends past my own working set,
taken as though it were local.**

> In a shared checkout, **`git add -A`, a pending migration, and the test
> database are all shared state.** Two of the three have now bitten. The third
> is closed by the advisory lock in `spec/rails_helper.rb`.

The uncomfortable part: I staged named paths deliberately all morning, for
exactly this reason, and then stopped. A discipline that is applied while it is
front of mind and dropped when it is not is the same failure as a check nobody
runs — which is why this is a rule in a file rather than a resolution.

### THE PRODUCTION IMAGE HAD NEVER BEEN BUILT, AND IT SHIPPED AN UNSTYLED CONSOLE

Built for the first time on **2026-09-17**. It builds — exit 0 — and the first
build found what a first build is for.

**`assets:precompile` was missing from `Dockerfile`, and `hatiwal-api` has it.**
There was a blank gap where the four lines belong.

Measured in the image rather than reasoned:

- `/rails/public/` contained **only `robots.txt`** — no `public/assets`.
- **Propshaft's server middleware is not in the production stack** (`[]`); it is
  development-only. `ActionDispatch::Static` is, and serves from `public/`.
- `stylesheet_link_tag "administrate/application"` **resolved perfectly** to
  `/assets/administrate/application-04100076.css`, because propshaft digests
  from the load path at runtime.

**So the page renders, references a stylesheet, and nothing serves it.** The
ops console — Hamma9900's only operational surface (correction 16) — would have
come up unstyled on his first deploy, with every gate in this repo green,
because nothing in a test suite builds an image.

Fixed by copying `hatiwal-api/Dockerfile:54-57` verbatim, comment included.
After: `public/assets` holds 45 files including the exact digest the HTML had
been asking for.

> **A DIVERGENCE FROM THE REFERENCE IS INVISIBLE FROM INSIDE THE FILE.** Nothing
> about our Dockerfile looked wrong — a missing step has no syntax. It was only
> findable by building it, or by reading the file it was copied from. Both of
> today's Dockerfile findings came from Hatiwal rather than from inspection.

### THE PRODUCTION IMAGE SHIPPED THE WHOLE TEST TOOLCHAIN — FIXED, AND IT IS A DELIBERATE DIVERGENCE

`brakeman`, `rubocop`, `rspec-*`, `factory_bot`, `faker`, `rswag-specs` are all
in the image — 153 gem directories.

**Cause:** `BUNDLE_WITHOUT="development"` excludes a gem only when **all** its
groups are excluded, and the Gemfile has `group :development, :test` plus a
separate `group :test`. Nothing in either group is dropped.

**Severity, stated honestly: bloat, not a break.** Production loads only the
default group plus the environment's, so those gems sit on disk rather than in
memory. The cost is image size, pull time, and a wider surface on a server he
administers alone from France.

**FIXED HERE as a DELIBERATE DIVERGENCE FROM `hatiwal-api`**, on Hamma9901's
call and recorded so it is legible later: Hatiwal has the identical line and the
identical Gemfile shape and ships them too, but **Karwan is not launching, so
the risk of correcting it is ours to take.** Hatiwal improves on its next build;
the finding went to Hamma9900 with that urgency — low, nothing new breaks, no
deploy blocked.

**This is the first time this repo has knowingly diverged TOWARD correctness
rather than away**, and that direction matters to whoever reconciles the two
later.

**Proven by running it, not by diffing a gem list.** `rswag-api` and `rswag-ui`
are in the DEFAULT group because they are mounted in production, and they
survive; only `rswag-specs` goes. 153 gem directories → 115. The rebuilt image
then booted against a real database and served
`/api/v1/public/merchants` **200** and a real `app_config` payload — **not
`/up`, which any Rails app answers**.

### READING THE PRECEDENT CORRECTED A CLAIM ABOUT OUR OWN REPO

Correction 15 says copy Hatiwal and name the file you read. It is written as
guidance on *how to build something*. On 2026-09-17 it did something else.

Writing the first-deploy rehearsal meant reading
`../../Hatiwal/DEPLOYMENT.md` for its shape. That file says migrations run
automatically on boot via `bin/docker-entrypoint` — so I opened ours, which I
had never done, and found it **byte-identical** (`diff` returns nothing). Our
entrypoint runs `db:prepare` whenever the container starts the server.

**That falsified a claim I had committed hours earlier**, in `44e9efa`: that a
deploy "runs neither" `db:prepare` nor `db:seed`. I had asserted a negative
about a file I had not opened — the exact failure this file records three times
over on the supervisor's side. The seed half stood; the sentence around it did
not, and both documents were corrected in place.

> **Reading the precedent is not only for how to build something. It is a check
> on what you believe you already have.** A reference implementation that
> solved the same problem describes YOUR repo too, wherever the two were copied
> from each other — so it is the cheapest available audit of your own
> assumptions, and it arrives while you are looking at something else.

**Closed by a gate, because the pairing it depends on is positional.** The
entrypoint fires only when the last two arguments are `./bin/rails` and
`server`, and the Dockerfile supplies them as
`CMD ["./bin/thrust", "./bin/rails", "server"]` — **nothing connects the two
files.** Appending a plausible flag is enough to break it silently, and the
symptom would be an app serving traffic with an old schema and nothing naming
a migration. `spec/config/entrypoint_migration_spec.rb` reads both files and
**executes the real condition against the real arguments**, so a change to
either side goes red.

### THE DEPRECATION CATALOGUE — 2026-09-17: ONE, ZERO OURS, RAILS 8.2

Measured across the whole suite with stderr captured (`config.active_support.
deprecation = :stderr` in test), plus a `zeitwerk:check` boot and a grep of our
own source for the classic removed APIs.

| | Count |
|---|---|
| Deprecation warnings emitted | **12 lines** |
| **Distinct root causes** | **1** |
| **Ours** | **0** |
| In a dependency we ship | **1** — `administrate` |
| Removed by | **Rails 8.2** |

The single cause is `administrate-1.0.0/lib/administrate/search.rb:114` —
`["%#{term.mb_chars.downcase}%"] * fields_count` — which emits both the
`String#mb_chars` and the `ActiveSupport::Multibyte::Chars` warnings from one
call. **Trigger: upgrade Administrate BEFORE Rails 8.2, not during**, and check
a fixed Administrate exists before the upgrade is attempted rather than
half-way through it.

**CONFIRMED ONE CALL SITE, NOT ELEVEN.** Driving search on every routed console
resource emits 22 warning lines from the same `Administrate::Search` line — the
per-resource dashboards share it, so the fix is one gem upgrade rather than
eleven changes.

Two other users of `mb_chars` exist in the gemset and **neither reaches us**:
`activerecord` itself, which is Rails' to fix before it removes the method, and
`annotaterb`, which is another project's gem in this shared RVM gemset and is
not in our `Gemfile`. Checked rather than assumed.

Our own code uses none of the classic removed APIs (`mb_chars`, `Multibyte`,
`update_attributes`, `render :text`, `before_filter`), and `zeitwerk:check`
eager-loads the whole app with no deprecation at all.

#### TWO THINGS ABOUT THE METHOD, AND THE FIRST ONE BOUNDS THE RESULT

**1 · A deprecation catalogue from a test suite is only as complete as the
suite's coverage.** Before `spec/requests/admin/operator_can_do_the_job_spec.rb`
existed, the full suite emitted **ZERO** deprecations — not because the app was
clean, but because **nothing exercised Administrate's search.** The most-used
feature of the console was invisible to the instrument until a spec drove it.

So this table means "one deprecation on the paths the suite covers", and the
honest way to widen it is to widen coverage. **Any path with no spec is a path
with no deprecation report**, which is the same shape as every other silence in
this file.

**2 · Rails reports the CALLER, not the emitter.** All six "called from"
locations were lines in my own spec file. Deduplicating by the reported source
gives **six** entries for **one** emitting site; deduplicating by the library
line gives the right answer. The key is where the deprecated call lives, not
where the request came from.

### THE OPS CONSOLE IS OPERABLE — five real tasks, driven, all possible

Everything proved before this was about the console's DATA being right. This
asked whether a non-developer can complete a job in it, by driving five real
operator tasks through HTTP rather than reading dashboards
(`spec/requests/admin/operator_can_do_the_job_spec.rb`).

| # | The task | Possible | Pages |
|---|---|---|---|
| 1 | A customer reads out an order code — find it, see status, courier, cash | **yes** | 2 |
| 2 | A courier says he was not paid — find him, read the ledger, credit him | **yes** | 3 |
| 3 | A restaurant says nobody collected — find it, reassign, audited | **yes** | 2 |
| 4 | A courier applied — find it, see what is missing, approve | **yes** | 2 |
| 5 | A fee is wrong — find the setting, change it, pricing reads it | **yes** | 2 |

**No `search_text` is needed on `orders` or `users`, and its absence is not a
gap.** Administrate searches every `Field::String` in a dashboard's
`ATTRIBUTE_TYPES` directly, which was suspected to be missing and is not.
Driven, not assumed: an order is found by its **code** and by the **customer's
phone**; a courier by **phone** and by **name**.

**Task 2's extra page is a real hop and it is already linked**: the user's show
page renders links to both `courier_wallet` and `courier_profile`, verified by
asserting the rendered paths rather than the dashboard constant. Search the
user, open him, click the wallet.

Nothing was missing, so nothing was added. Recorded because **a clean result
that is not written down gets re-audited**, and because the page counts are the
baseline any future console change should be measured against.

### FOUR AUDITS THAT CAME BACK CLEAN — 2026-09-17, recorded so nobody redoes them

**An audit whose clean result is not written down gets repeated.** Each of
these was a real question, checked properly, and answered no. Three are now
held by a gate rather than by this paragraph, which is the difference between
*verified in September* and *still true*.

| Question | How it was checked | Answer | Held by |
|---|---|---|---|
| Do any admin interventions write no audit row? | Drove all **18** custom admin actions and asserted a row with an actor | **All 18 audit.** A count had suggested four gaps; two artefacts explained it — `merchants#open/close` share a private `toggle` that audits, and `mark_settled`/`reject_amount` sit below `private` and are helpers, not actions | `spec/requests/admin/every_intervention_is_audited_spec.rb`, enumerated from `Rails.application.routes` |
| Is one-way door 6 (soft delete) unimplemented on three of its four names? | Grepped `include SoftDeletable` and `deleted_at` in `db/schema.rb` | **Covered.** Five models, not three: `merchant`, `user`, `catalog_item`, `catalog_category`, `address`. Restaurants → merchants, **riders → users**, menu items → catalog_items, addresses → addresses | — |
| Can the console hard-delete anything holding money or history? | Read every admin `resources … only:` list | **No.** `destroy` is routed for `merchants` alone; not for users, wallets, orders, wallet_entries, settlements or audit_logs — so the `User → wallet → wallet_entries` cascade is unreachable | `delete_is_discard_spec.rb`, six examples asserting no destroy route exists |
| Does any Administrate form bypass a model mechanism? | Read every dashboard's `FORM_ATTRIBUTES` | **No.** `CourierWalletDashboard` is `[:credit_line]` so balance cannot be typed past `record_entry!` (door 4); `OrderDashboard` and `TripDashboard` are `[]` so status cannot be set past `Order::TRANSITIONS` (door 3) | — |

**The one that was NOT clean is recorded separately below** — `merchants#destroy`
hard-deleted a soft-deletable model. It is the same class as the fourth row
(Administrate's generic CRUD bypassing a model mechanism) and it was the only
instance; the others above are the negative result of looking for siblings.

**The method note, since three of these started as a grep that was wrong in the
same way:** each mistaken claim was a **negative** derived from a pattern
search — "only three models have soft delete" came from grepping
`discard|deleted_at` across `app/models/*.rb`, which finds nothing in a model
that includes a `SoftDeletable` **concern**. A grep for symptoms cannot produce
a trustworthy negative. Find the mechanism, then grep for its inclusion.

### THE CONSOLE'S DELETE BUTTON HARD-DELETED A SOFT-DELETABLE MODEL — CLOSED

`Merchant` includes `SoftDeletable` and implements `discard_dependents!` to
hide its catalog with the shop. **Administrate ships a `destroy` action that
calls `destroy`**, so the console bypassed the whole mechanism and hard-deleted,
cascading `dependent: :destroy` onto `catalog_categories` and `catalog_items`.

Measured by driving it, because reading the controller showed nothing wrong —
there was no code to see. A merchant with a catalog and no orders: row gone,
**0 catalog items left**, HTTP 303 as though it had worked. `discard_dependents!`
was **called by nothing**.

Bounded by an unrelated guard: `has_many :orders, dependent:
:restrict_with_error` refuses any merchant that has ever traded, so there was
never a hole in the books. The real cost was a newly onboarded restaurant
losing the menu somebody sat and typed in — the exact user Hamma9900 is
hardest-won.

**Bounded is not intended.** The model said discard and the button said
destroy. Now `Admin::MerchantsController#destroy` discards, hides the catalog,
and audits who did it.

### NOTHING RUNS `db:seed` ON A DEPLOY, SO THE CONSOLE WOULD BE EMPTY

`config/deploy.yml` defines `migrate` and `seed` under **`aliases:`** — they
are shortcuts a person types, not hooks — and there is **no `.kamal/hooks/`
directory**.

**CORRECTED 2026-09-17, by reading `bin/docker-entrypoint` instead of trusting
this paragraph's first draft.** I originally wrote "so a deploy runs neither",
and the migration half of that is **wrong**:

```bash
if [ "${@: -2:1}" == "./bin/rails" ] && [ "${@: -1:1}" == "server" ]; then
  ./bin/rails db:prepare
fi
```

**`db:prepare` DOES run automatically**, on every container that starts the
server — byte-identical to `hatiwal-api/bin/docker-entrypoint`. So the schema
is always current after a deploy and the `migrate` alias is belt-and-braces.

**NARROWED AGAIN 2026-09-17, by running the image rather than reading it.**
The first production container booted against a real database and logged
**"Seeding complete."** — because `db:prepare` **creates, loads the schema AND
RUNS SEEDS when the database does not yet exist.** Verified: 48 `settings` rows
in a freshly created `karwan_production`, and `/api/v1/public/app_config`
answering with real JSON.

So **a FIRST deploy seeds itself** and the Config screen is fully populated. My
earlier "the console would be empty on a fresh deploy" was wrong.

**The genuine gap is the second deploy onward.** Once the database exists,
`db:prepare` only migrates — it does not re-seed. So **a `Setting` added in a
later release never materialises on the running server**, and `Setting.fetch`
silently serves its code default while the console has no row for it. That is
the realistic case, it recurs with every release that adds a knob, and it is
exactly what `bin/preflight`'s config-rows check catches — which makes that
check more valuable than when it was written, not less.

`kamal seed` after every deploy remains the fix, and is safe: the reference half
is idempotent and never overwrites a tuned value.

**The failure is quiet, which is what makes it worth writing down.**
`Setting.fetch` falls back to the definition's default when no row exists, so
the app boots, prices orders and delivers food on values nobody can see. The
console lists **rows**, not definitions — so the Config screen is simply short,
and correction 13's entire premise ("he retunes numbers weekly from the console
with no deploy") quietly does not hold. There is no error anywhere.

**Verified 2026-09-17 that the seeding itself is correct**:
`spec/requests/admin/config_reachability_spec.rb` proves all 42 definitions
materialise and that each row renders an input he can type into. **That spec
proves `seed_defaults!` works. It does not prove anybody runs it** — which is
the exact distinction TESTING.md now carries, arriving from a third direction.

**CLOSED as far as it can be closed here, and the fix is not a hook.**

`hatiwal-api` has the identical gap — `.kamal/hooks/` holds nothing but Kamal's
untouched `.sample` files, which do not execute, and its `deploy.yml` puts
`migrate` and `seed` under `aliases:` exactly as ours does. **The app in
production with real users also seeds by hand on deploy** (its migrations run
from the same entrypoint ours do), so manual is the
established practice in this owner's deploys rather than an oversight here.

Two things follow. There is **no Hatiwal mechanism to copy**, so a hook would
be an invention — correction 15 says an invention comes to Hamma9901 first with
its cost. And the defect is therefore not "no automation": **it is that
forgetting is invisible.**

So what shipped is a check in `bin/preflight`, which is verifiable on this box
and catches the general case rather than one forgotten command: every key in
`Setting::DEFINITIONS` must have a row, missing ones named, warn locally and
**fail on a deployed box** — the same split as the SMTP check. **It found two
genuinely missing rows on this box on its first run**
(`courier_topup_enabled`, `courier_min_earnings_per_km`, added that afternoon
and never seeded), which is the failure it was written for, caught live before
it was committed.

`docs/RUNBOOK.md` now carries `kamal seed` as a numbered step of a first
deploy, with why forgetting it is silent.

**The hook is still the eventual answer**, with the shape above. **Its trigger
is the deployment work itself** — it must be written and verified against a
real deploy, which is the one context that can prove it, and that context is
definitely coming.

### THE PREMIUM UPLIFT IS CHARGED AND NEVER COLLECTED — OPEN, HAMMA9900'S

Found by `spec/services/pricing/money_conservation_spec.rb` on its first run.
**Live money, on the only paid upgrade the product has.**

Measured, 400 AFN order at 12.5% commission:

```
normal   customer 480  merchant 350  courier ends with  80  platform 50
premium  customer 504  merchant 350  courier ends with 104  platform 50
```

The customer pays **24 AFN more for premium and the courier keeps all 24.**

**No single file is wrong, which is why nothing caught it.**
`Pricing::DeliveryQuote` states *"THE PREMIUM UPLIFT IS THE PLATFORM'S"* and
`Order` states *"the platform's delivery margin is `delivery_fee -
courier_fee`"* — both correct as intent. But in Model A the courier collects
`customer_total`, hands over `merchant_payout`, and his wallet is charged
`commission`. **Nothing charges him the margin.** `Couriers::CashPosition` sums
`commission` alone; `Order#platform_cash_held` returns `commission` alone. Each
file is locally consistent and the money goes missing between them.

**Not fixed here: whether the courier owes the premium margin is a money rule**
(HOW_WE_WORK — his). It sits as a `pending` example naming him, which turns
green the day it is fixed and fails loudly if anybody "fixes" it by editing the
expectation. A second example pins what is true today so the leak cannot grow
while the question is open.

**It is probably the same decision as the §2 disagreement**, and worth putting
to him as one: both are *where does platform revenue get collected in a cash
model where the courier physically holds every note*. §2's answer — the
restaurant as the single collection point for both sides — would answer this
one too. Answering them separately is how a third inconsistency appears.

### A TRIGGER NOBODY CAN OBSERVE IS NOT A TRIGGER — SWEPT, ONE FOUND

Every deferral in the docs was re-read on 2026-09-17 against one question: **can
a person on this box observe the condition that would end it?**

**One failed.** `/customer/orders/active` deferred on *"if the status screen
ever feels slow on a real Kabul connection"*. Nobody here has one, and "feels
slow" is not recorded anywhere — so the deferral could never end, by anybody,
ever. Rewritten to a number the rig can print.

**The rest hold, and are worth naming so nobody re-audits them:**

- `REALTIME_AND_SCALE.md` §2 — switch to ActionCable at p95 > 200ms, sustained
  load > 40% of capacity, ~5,000 concurrent jobs, or contention on
  `courier_profiles`. Not observable today because nothing is deployed, but
  each is a number that exists the moment it is, and the doc says "do not do it
  before the numbers say so".
- `SERVICE_TIERS_AND_BATCHING.md` — paid placement revisited "when the list no
  longer fits on one screen". Observable by opening the app.
- The OpenAPI deferral — "a consumer outside this repo needs to call the API".
  An event, not a measurement, and an unmissable one.

**The distinction the sweep produced**, which is the transferable part: *waiting
on production* is honest and ends by itself, because the numbers arrive with the
traffic. *Waiting on a condition nobody records* never ends. Both look identical
in a document. Ask who would notice, and when.

### CONSERVATION IS NOT ATTRIBUTION, AND A RESIDUAL CANNOT FAIL

The first version of the conservation spec defined the courier's share as
`customer_total - merchant_payout - commission` — **a residual**. It therefore
summed to `customer_total` by arithmetic, and the conservation assertion could
not fail across 101 examples. Caught by planting a leak and finding nothing
went red.

Rebuilt so every share is computed from **independent stored fields**
(`merchant_payout`, `courier_fee + topup`, `commission - topup + delivery_fee -
courier_fee`). The same plant now turns **50 of 126** examples red.

**The boundary, which shaped the file and is worth keeping:** conservation
catches money appearing or vanishing. It does **not** catch the wrong party
being paid — re-attributing the premium uplift from the platform to the courier
conserves perfectly, which is exactly the live bug above. So the file asserts
both: conservation over the matrix, and attribution (`intended` versus
`actual`) per party. A test that only conserves would have been satisfied by
the defect it was written to find.

### THE TOP-UP AT A CALL SITE WAS A BUG, AND THE FIX WAS STRUCTURAL — CLOSED

Recorded because the reasoning generalises well past this feature.

`Pricing::CourierTopUp` was first called from `offers#accept`, and I wrote it
up as an open product question: *should a hand-reassigned job be topped up at
all — his money, his call?* **That framing was wrong, and Hamma9901 was right
to reject it.** The decision Hamma9900 already made is *pay a courier properly
for a thin order a long way out*. **How the courier came to hold the job is not
a dimension of that policy** — he rides the same dead leg either way. Paying
him less because a human assigned him rather than the algorithm is not a policy
anybody would choose; it is an inconsistency nobody would ever see, because
both orders look correct on their own.

**And the fix was not a second call in `reassign`.** It moved onto the
assignment itself — `Order#freeze_courier_pay`, the `after_save` that already
freezes `courier_fee` from the courier's vehicle rate. Every path that assigns
a courier passes through it, **including the ones that do not exist yet.**

> **A second call site is a third one waiting to be forgotten.** This is the
> same shape as a check nobody runs and a guard nobody calls, both of which
> this repo has already paid for: a rule that must be REMEMBERED at each site
> will eventually not be. Put it where the thing it depends on already lives,
> so it cannot be omitted rather than must not be.

Two properties came free from the move and are asserted:

- **The ordering is structural rather than remembered.** The top-up measures
  the shortfall against the fee being computed on the line above, so
  `self.courier_fee = fee` happens in memory before it is asked for. At a call
  site this was a thing to get right; here it is the only thing that can
  happen.
- **A reassignment CLEARS a top-up the new courier does not qualify for**,
  because the callback returns 0 rather than nil. Otherwise a courier standing
  at the merchant's door would inherit the previous courier's 4 km.

### A RIDE HAS NO SHORTAGE MULTIPLIER — HIS DECISION, NOT AN OVERSIGHT TO FIX

`Pricing::DeliveryQuote` reads `Pricing::ShortageMultiplier`; `Pricing::RideQuote`
does not, and `trips` has no column for it. A storm raises delivery fees and
leaves fares alone.

**This is very likely an omission rather than a decision.** Hamma9900's
instruction was that the storm switch lifts the customer's fee *and* the
courier's pay together, and he was describing delivery because delivery was
what we were discussing. A storm with no taxis on the street is the same market
fact about the same courier pool — which is the whole business thesis.

**But it is his, and it is not close.** It changes what a passenger pays, and a
ride fare is quoted upfront and frozen precisely so a passenger can verify it
before getting in (correction 13). A multiplier nobody told them about is the
trust problem this platform exists to solve, arriving from our side.

**What it would take, so the answer is cheap when it comes:** a
`shortage_multiplier` column on `trips`, two lines in `RideQuote`, and the
`Pricing::Quote` fields that already exist. The module takes a tier and returns
a multiplier and needs no change. Half a day, and it stays OUT until he says.

### THE `merchant_payout` COUPLING — recorded against the decision itself

`merchant_payout: items_total - commission` contradicts MONEY_AND_SETTLEMENT.md
§2 and is waiting on one sentence from Hamma9900. **The note that matters is
now in that document, beside the decision**, rather than only here: the day the
line changes, `Pricing::CourierTopUp` must be re-read in the same pass, because
its entire safety argument is "we never touch `commission`, so
`merchant_payout` cannot move".

Written there rather than in a commit body or a supervisor's head, because his
answer may be days away and a decision that silently invalidates a safety
argument elsewhere is the worst kind to take alone.

### `/courier/wallet/entries` HAS NO CALLER — AHEAD OF ITS SCREEN, NOT DEAD

Said plainly because this repo's own habit is to delete or "fix" an endpoint
nothing calls, and here that would be wrong. `src/screens/courier/` contains
`Apply.tsx` and `Job.tsx` and **there is no wallet screen** — ROADMAP records
that as a deliberate cut, *"balance and fundability already appear on the offer
card, at the moment they matter."*

So the endpoint is waiting for a screen rather than orphaned by one. **What
depends on it:** the courier-facing copy for a `commission_topup` entry. There
is nothing to render a string today, so no placeholder was invented — a
placeholder nothing displays is translation debt created out of nothing. The
ledger note carries the ARITHMETIC for an operator instead, because the console
is where a complaint is actually answered. When the statement screen is built,
the Pashto gets written by somebody looking at the screen.

**The distinction worth keeping:** a guard with no caller is dead and dangerous
because it *claims* to protect something. A read endpoint with no caller is
merely early. The test is whether anything would be worse if it were deleted —
and here, the day the screen is built, it would be.

### AN UNAPPLIED MIGRATION TAKES THE SHARED DEV API DOWN FOR EVERY SESSION
Generating `20260917130559_add_shortage_multiplier_to_orders.rb` and not
applying it to **development** put `/api/v1/public/app_config` and
`/api/v1/public/merchants` on HTTP 500 for every session on this box, and
blocked a 21-flow device run that had nothing to do with pricing.

**The symptom names nothing.** `check_pending_migrations` refuses every
request, including the pre-auth public ones, so it reads as "the API is
broken" from a session that never touched the schema — and the session that
did touch it is running its own suite against its own test database, where
everything is green.

Two rules out of it:

- **Generate and apply in the same breath.** A pending migration is not a local
  inconvenience on a box where `karwan_development` is shared by the API
  server, the QA rig and every other session.
- **Nobody else can fix it for you**, and Karwan [9d4e65] was right to refuse:
  `db/schema.rb` was modified in the migrating session's working tree, so a
  `db:migrate` from another session would have regenerated it underneath an
  in-flight edit. That is the same cross-session collision `TEST_DB_SUFFIX`
  exists to stop, arriving through a different door.

### A CHECK THAT CANNOT FAIL, WRITTEN BY SOMEBODY WHO HAD JUST READ THE RULE
The shortage multiplier's most important property is that **the platform keeps
none of the uplift** — the customer pays more because the courier is paid more.
It was asserted as:

```ruby
expect(amounts[:delivery_fee] - amounts[:courier_fee]).to eq(0)
```

which is true when both sides rose together **and equally true when neither
moved at all**, because the customer's fee is derived from the courier's.
Planting `courier_fee = base_delivery_fee` — deleting the whole feature — left
it green.

It now asserts the storm ARRIVED as well as that we did not keep it. The
transferable part is not "check two things": it is that **an invariant stated
as a difference is satisfied by zero on both sides**, and zero-on-both-sides is
exactly what deleting a feature looks like. Any assertion of the form `a - b ==
0`, `a == b` or `ratio == 1` needs a second one saying the pair is not at rest.

Worth recording precisely because the rule was already known and written down
two files away. **Reading the rule is not the same as applying it to the line
you are typing**, which is why the plant matters more than the rule does.

### GREPPING `app/` IS NOT GREPPING THE CALLERS
`Pricing::Quote#to_attributes` looked order-only: a grep across `app/` returned
exactly one caller, `Orders::PlaceService`. So two order-specific keys went into
it — and the RIDE specs went red, because they build a `Trip` from the same
method and `trips` has no such column.

The second consumer was in `spec/`. A shape used by a test is still a shape
somebody depends on, and in this case the test was the honest one: it was
asserting that a quote can fill a trip, which is a real contract.

Fixed at the right seam rather than by adding dead columns to `trips`:
`to_attributes` stays what every consumer can accept, and `Orders::PlaceService`
merges the two delivery-only keys itself. **A shortage applies to deliveries
today and to rides when somebody builds it** — the asymmetry is now stated in
the code rather than implied by a column nothing writes.

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

### A CLASS BODY THAT REACHED INTO ANOTHER MODEL WAS A PRODUCTION BOOT FAILURE
`CARRIES` and `SEATS` lived on `CourierProfile`, and `Trip`, `Order` and
`PricingRate` read them **in their class bodies** — `CourierProfile.vehicle_types`
and `CourierProfile::SEATS`. That makes two models load-order dependent, and
under eager loading `Trip` could be reached while `CourierProfile` was still
part-way through its own body:

```
app/models/trip.rb:79: uninitialized constant CourierProfile::SEATS (NameError)
```

**It passed `zeitwerk:check`, passed all 1,304 examples, and reproduced only in
`RAILS_ENV=test bin/rails runner`.** Production eager-loads, so it was a boot
failure waiting for a load order nobody had hit — and the first person to hit
it would have been Hamma9900 on a deploy.

Fixed by moving the vocabulary, the capacities and the seat counts into
`VehicleTypes`, a plain module that depends on nothing — the same shape as
`Roles` and `SizeClasses`. **A shared vocabulary belongs in a module every
model can read without loading another model.** A spec now greps for the old
references, because the fix is only durable if nobody reintroduces one.

Two smaller lessons from the same hour. The tell was in the output and I nearly
skipped it: `warning: already initialized constant CourierProfile::STALE_AFTER`
means a class body ran TWICE, which is the signature of a load cycle rather
than noise. And my first attempt at the fix **deleted 129 lines** — associations,
validations, scopes and the enum I had just added — because I sliced from a
heading to `s.index("  enum :vehicle_type,")` and that anchor appears EARLIER in
the file, so the slice ran backwards. The redo asserted that the only code lines
removed were the constants being moved, and that check is what made the second
attempt safe.

### FCM data values are stringified, so anything structured must be encoded
`FcmClient` runs every data value through `to_s`, because FCM's data map is
string-to-string. An array of symbols therefore arrives as the literal
`"[:id_document, :selfie]"` — Ruby inspect output the app would have to parse
as Ruby. The courier review alert now JSON-encodes its `missing` list on
purpose.

Caught by a spec asserting the values were strings. Worth generalising: **any
structured value crossing a string-typed boundary has to be encoded
deliberately, or it ships as debug output.**

### A review that ASKS is not a refusal, and needed its own state
`verification_status` had pending / approved / rejected / suspended, so "we
asked you for a better photo" could only be expressed as a refusal — and the
console operator's only options were approve or reject. An applicant told he
was refused when he had merely forgotten a photo is a courier we convinced and
then lost, on the side of the market that is scarce.

`needs_more` (4, appended) plus `ask_for_more!`, `review_note` for what a human
noticed that a validation cannot, and a push per outcome. Three outcomes, three
messages, and the specs assert they are not the same message.

**The fixture lesson, again, caught by a plant:** my first test asserted that
asking for more leaves `rejection_reason` nil — on a profile that had never
been rejected, so nil either way, and deleting the clearing line broke nothing.
The fixture has to REJECT first and then ask, which is also the only real case:
a reviewer who refused somebody and thought better of it is exactly who uses
that action.

### The tier shipped before batching, because consent cannot be retrofitted
`orders.service_tier` and `trips.service_tier`, frozen at placement, with
nothing batching yet. That is deliberate and it is the cheap direction: a tier
without batching is a price difference that costs nothing to honour — we simply
never batch, and `batch_max_jobs` ships at **1** — while batching without a
recorded tier is unshippable, because no past customer can be asked whether
their completed order could have been shared.

`premium_price_multiplier` is a `Setting` rather than a `pricing_rates`
dimension, because the uplift is the same proportion whatever the vehicle and a
tier axis would double every row to express one number. That is the same rule
as everywhere else here: **scalars are settings, per-vehicle things are rows.**

**An unrecognised tier becomes `normal`, never `premium`.** The default is the
cheaper, less-promising one, so a stale client cannot sell somebody an
exclusivity they did not ask for and cannot fail an order over a word.
Charging more than a customer chose is the one mistake on this path that costs
trust rather than money.

### THE COURIER INCENTIVE ON A PREMIUM JOB IS BACKWARDS ONCE BATCHING SHIPS
Recorded now because it will not be obvious later, and it is a number rather
than a redesign.

On a delivery the premium uplift is the **platform's**: what premium buys is
the capacity we hold empty, and the courier is paid for the run he did, from
the courier rate for his vehicle. That is right today, when nothing can be
batched and he gives up nothing.

**The moment batching is switched on it inverts.** A premium job would then pay
him the same as a normal one while forbidding him to combine it — so couriers
would prefer normal work, and premium customers, who paid more, would wait
longest. The fix is to share the uplift with him at that point.

A RIDE already behaves correctly and the asymmetry is Model A's two shapes
rather than an oversight: there the fare IS the courier's revenue and we take a
percentage, so a premium fare lifts both sides automatically.

### The order code has to survive a pen and a phone call
`SERVICE_TIERS_AND_BATCHING.md` §6. It was `K` + `yymmdd` + 4 digits — eleven
characters, six of them a date that told a human nothing, because support
searches by code and not by day. Now a prefix plus six digits: seven
characters, said in one breath over a bad line.

**Digits only, and that is the whole of the unambiguity requirement rather than
laziness:** every collision §6 names is between a digit and a LETTER — 0/O,
1/I/l, 5/S, 8/B — so an alphabet with no letters cannot have them. A base32
code would be shorter for the same entropy and would reintroduce all four,
which is why there is now an example asserting the alphabet rather than only
the length.

One generator, in `Dispatchable`, because orders and trips had the same format
duplicated and only one of them got shortened first.

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

---

## The password login — what is honest about it, and what is still open

Landed 16 Sept 2026 (see `REQUIREMENTS.md` and `IDENTITY_AND_ROLES.md` §1/§5).
The gaps below are recorded because they are real, not because they are
blocking.

**1. The reset endpoint has a residual TIMING difference, and it is not closed.**
`POST /auth/password_reset` returns an identical status and body whether or not
the account exists, and the bcrypt cost of issuing a code is spent either way so
the dominant CPU asymmetry is equalised. **Delivery is not**: a found account
sends an SMS or enqueues mail, and an unknown one does nothing. That is
measurable from outside with enough samples. The mitigations are the IP throttle
(20/hour, tighter than sign-in) and the fact that the *message* — the part
Hamma9900's instruction was about — is identical. Closing it properly means
enqueuing a no-op job for the unknown branch; noted rather than done, because it
trades a real oracle narrowing for a queue full of decoy jobs.

**2. Being THROTTLED implies an account exists.** `reset_throttled` is only
reachable when a code was actually issued, so a script that sees it learns the
identifier is real. Accepted deliberately: the alternative is a silent no-op,
which leaves somebody who genuinely forgot their password tapping a dead button
with no idea they have to wait. A dead end for a real user is worse than a slow
leak to an attacker who could learn the same thing by other means.

**3. `phone_verified_at` is now always nil, and stays in the schema.** The only
thing that ever set it was the OTP sign-in, which is switched off, and
registration leaves it nil because there is no verification step. It is not
removed because the column is where a verification step would land if Hamma9900
ever wants one, and because "no verification" is a *product* decision that could
reverse, unlike the one-way doors. **Do not write code that reads it as
meaningful**; today it encodes nothing.

Both seed files were still stamping it, which made every fixture account
`phone_verified: true` while every real account is false — a state the app can no
longer produce, found by reading the field off a live HTTP sign-in rather than
out of a spec. Now unset in both. Nothing branches on it (one serializer field,
one console column, no policy, no client), so the visible effect is that the ops
console shows fixtures the way it shows real users.

**4. Accounts with no password exist and must keep working.**
`encrypted_password` defaults to `""` rather than being backfilled, so every
account that ever signed in with a code has one. They are not locked out — they
reset — and critically they are **not distinguishable** from a wrong password at
the login, or the oracle reopens through the back. The `:passwordless` factory
trait exists to keep that case testable.

**5. The email reset cannot be end-to-end verified here.** SMTP takes four
environment variables and there is no mail server on this box, so the mailer is
proven at the message layer (`UserMailer.password_reset` — recipient, code in
both parts, RTL, LTR-isolated digits, Setting-driven copy) and the delivery is
`deliver_later` into solid_queue. **Verified at the layer below the wire**, and
that is the honest sentence: nobody has watched this email arrive.

**6. The QA rig's sign-in step changed shape and the mobile half is not done.**
`db/seeds/e2e.rb` now sets `E2E_PASSWORD` and gives each fixture account an
email; `qa/lib/common.sh` in karwan-mobile holds the other half of that contract
and still expects to read a code out of `POST /auth/otp`, which now answers
`otp_disabled`. **That is a clear failure rather than a confusing one**, which is
why it was left rather than reached across the repo boundary. It has to change
with the mobile sign-in screen, in one pass.

**7. Three endpoints where there used to be one.** Registration is now separate
from sign-in, because a password forces it — "sign me in" needs the account to
exist and "make me an account" needs a password chosen. The mobile app therefore
needs **two** screens' worth of API calls where it had one, plus the reset. That
is queued with the sign-in screen and the 16 held locale keys.

---

## There is no concept of a CITY anywhere, and that is the first thing a second one needs

**Verified 2026-09-16, not assumed:** `grep -n "city" db/schema.rb` returns
nothing. No `cities` table, no `city_id`, no zones, no service areas. A merchant
is a latitude and a longitude; a customer finds one by **distance alone**; a
courier is dispatched by **distance alone**.

**That is correct for one Kabul neighbourhood** and should not be changed now.
Everything within a few kilometres of everything else makes a city column pure
overhead — a field every form must set, every seed must fill and every query
must remember, protecting against nothing.

### What breaks on the day a second city opens, in the order it breaks

1. **The customer's merchant list.** `/public/merchants` sorts by distance with
   no floor, so a Jalalabad customer sees Kabul restaurants — far down the list,
   but present, and orderable. **This is the one that reaches a real user
   first.**
2. **Dispatch.** Partly guarded now: `dispatch_max_offer_radius_km` puts a
   ceiling on how far a courier may be from the pickup
   (`Dispatch::Eligibility#too_far?`). That stops the 150km offer, but it is a
   *radius*, not a *boundary* — two cities 10km apart would still bleed into
   each other.
3. **Pricing.** One set of `pricing_rates` for everywhere. A per-km rate tuned
   for Kabul is not a Jalalabad rate, and there is no axis to vary it on.
4. **The admin console.** Every list is global. The first operator in a second
   city sees, and can act on, the first city's orders and wallets.

### It is NOT a one-way door, and that is why this is a note rather than work

**Coordinates can imply a city later.** Every merchant, address, order and trip
already stores a latitude and longitude, so a `cities` table with a bounding box
or a centre-plus-radius can be backfilled by assignment — no data is missing and
nothing has to be reconstructed. That is the test `CLAUDE.md`'s one-way-door
section sets, and this passes it: what we are failing to record is nothing,
because position is already recorded.

**So the trigger is a business event, not a code smell.** The day Hamma9900
says a second city, this becomes a real piece of work of perhaps two days —
table, backfill, scope the four things above. Nobody should discover it while
trying to launch.

---

## THE CODE AND `MONEY_AND_SETTLEMENT.md` §2 DISAGREE ABOUT WHO OWES THE COMMISSION

**Found 2026-09-16 while reading §2 before touching `delivery_quote`, which is
exactly what Hamma9901 said to do. Not fixed — it is a money-model change and
needs Hamma9900's word, not my inference from a document I did not write.**

### The disagreement, in his own 300 AFN numbers

| | `MONEY_AND_SETTLEMENT.md` §2 and §3 | `Pricing::DeliveryQuote` today |
|---|---|---|
| Courier pays the restaurant | **300** (the food, plus the platform's delivery margin) | **250** (`items_total − commission`) |
| Courier ends holding | his fee, and **nothing of ours** | his fee **plus our 50** |
| Who owes the platform the 50 | **the restaurant**, in its weekly deposit | **the courier** |

The doc is unambiguous — §3's table reads *"Food courier | **never directly** |
the platform's share reaches it via the restaurant"*, and §2 calls a debt-free
courier *"the single biggest simplification in the model."* The code implements
the **superseded** Model A from `CLAUDE.md`'s own money section: *"Rider pays the
restaurant 350 (400 food − 50 our commission) … Rider is left holding our 50."*

### Where it lives, exactly

`app/services/pricing/delivery_quote.rb:51`

```ruby
merchant_payout: (@items_total - commission).round(2),
```

Under §2 that becomes `items_total + platform_delivery_margin`. And the courier's
commission `wallet_entries` on the food side stop being written at all.

### What is NOT in disagreement, checked rather than assumed

- **The platform's margin on the delivery fee is already expressible and is
  deliberately zero today.** `delivery_fee = base_delivery_fee × tier_multiplier`
  while `courier_fee = base_delivery_fee`, so on a normal tier they are equal and
  the platform takes nothing from the courier's side. §2 says exactly that, and
  says not to widen it *"while begging for couriers."* Code and doc agree.
- **The premium uplift is already the platform's**, which is the same mechanism
  at a different multiplier.
- **Rides are unaffected.** §3: the taxi driver is the one party who genuinely
  owes money, because he collects the whole fare and there is no third party to
  route a share through — so the wallet, balance and deposit machinery stays.

### The consequence nobody should be surprised by

**Under §2 the courier advances MORE, not less** — the full food price instead of
food-minus-commission. So `CourierWallet#can_fund?` becomes **stricter**, not
looser: a wallet that can fund a 250 advance today might not fund a 300 one. The
change removes the courier's *debt*, not his *float*. Anyone reading "couriers
owe nothing" as "the wallet check can relax" would have it backwards.

### Why this is recorded rather than done

`MONEY_AND_SETTLEMENT.md` is binding and says one thing; the ledger does another;
and the deleted §6 of that same document carries the rule for this situation —
**"do not implement this by guessing."** The change is small to write and large to
be wrong about: it moves who owes whom, it changes what the courier's step screen
says ("pay 300", not "pay 250"), and it makes a whole category of
`wallet_entries` obsolete on the food side while leaving it live on the ride side.

**It needs one sentence from Hamma9900 and then it is an afternoon.**

## OBSERVED ONCE: an order-dependent failure in `couriers/wallet_spec.rb`

**Recorded because it passed on the retry, which is exactly why it would
otherwise be forgotten.**

On 2026-09-17, a full-suite run failed one example:

```
rspec ./spec/requests/api/v1/couriers/wallet_spec.rb:182
  GET /api/v1/courier/wallet/entries never shows another courier's entries
```

It then passed in all three of: that file alone (20 examples), that file paired
with `spec/seeds/e2e_spec.rb` (68 examples), and a second full run (**1849
examples, 0 failures**).

`spec/spec_helper.rb:91` sets `config.order = :random`, so **this is an
order dependency rather than flakiness** — a different permutation surfaced it
and the next one hid it. I did not capture the seed, which is the mistake:
RSpec prints `Randomized with seed NNNN` and that number is the only way back
to the failing permutation.

**What it is probably about, stated as a hypothesis and not a finding:** the
example asserts isolation — one courier must not see another's ledger. The e2e
seed now creates **five wallet entries** for `E2E[:courier]`, and if some
permutation leaves those rows visible to that example, the isolation assertion
sees entries it did not create. Every write in that seed is inside the
per-example transaction, so this should not happen; that it apparently did once
is the part worth someone's attention.

**If it recurs:** capture the seed from the run's output and
`bundle exec rspec --seed NNNN --bisect`, which reduces it to the minimal pair
of examples. Do not re-run hoping for green — a passing retry of an
order-dependent failure is the "run it twice" rule giving the wrong answer,
because the second run is a different experiment rather than a repeat of the
first.

