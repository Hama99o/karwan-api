# Testing — the contract

The owner's instruction, verbatim:

> "we test each method each endpoint eeach policy each serilizer each service in
> backend do not forget this"
> "rspect test evrething and unit test also and later we will do end to end and
> qa also note these thing"

So: **every layer, now. E2E and QA later — later, not never.**

"test" in this repo always means **backend RSpec**. Never frontend. (Same
convention as `hatiwal-api` and `edu-safi`.)

---

## BEFORE YOU WRITE A GATE: `bin/gates`

```
bin/gates            # every spec file and what it asserts, grouped by directory
bin/gates admin      # filtered by path
```

**Run it first. The gate you are about to write may already exist.**

On 2026-09-17 a session built a spec driving index, search and show for every
console resource — derived from the router, planted red, the lot.
`spec/requests/admin/dashboards_spec.rb` had done the index and show half since
before that day **and had already caught the thing it was built for**:
`users.active_role` renamed to `users.last_active_role`, 1,078 examples green
while `/admin/users` would have died on its first request.

The duplicate was found three hours later, by accident, while listing spec
constants for an unrelated sweep. **The question "does a gate for this already
exist?" had no cheap answer, so it was answered by writing the gate.** This is
the cheap answer, and it is derived from the tree so it cannot go stale the way
a hand-written index would.

It is also the practical antidote to the eighth shape below: an instrument whose
DOMAIN was chosen somewhere else is far easier to notice when every domain in
the suite is on one screen.

`spec/config/gates_listing_spec.rb` asserts it speaks for **every** spec file,
because a listing that silently omits one is worse than no listing — it answers
"no such gate" with authority.

---

## What must exist, per thing you change

| You changed | The spec that must exist |
|---|---|
| A model | `spec/models/<model>_spec.rb` — validations, associations, enums, **every public method**, every scope |
| A controller action | `spec/requests/api/v1/<controller>_spec.rb` — rswag: happy path, auth failure, validation failure |
| A policy | `spec/policies/<model>_policy_spec.rb` — **and** a request spec proving the refusal AND the legitimate path |
| A serializer | `spec/serializers/<model>_serializer_spec.rb`, or the request spec asserting the exact keys |
| A service | `spec/services/<service>_spec.rb` — including the failure branch and the transaction rollback |
| A model | a FactoryBot factory, always |

### The authorization rule, stated separately because it is the one that gets skipped

Every authorization change needs a request spec proving **both** halves: that the
wrong user is refused, and that the right user gets through. edu-safi had five
endpoints where the correct scope existed, was correct, and **was never
consulted** — a policy spec alone would have passed on every one of them.

### The money rule

Anything touching money needs an audit entry and **a test that the parts sum to
the whole**. `Order#totals_add_up` and `OrderItem#line_total_matches_parts` are
those tests at the model layer; an endpoint that computes a total needs its own.

---

## Before every commit

```bash
bundle exec rspec       # zero failures
bundle exec rubocop     # zero offenses
```

And when request specs changed:

```bash
bundle exec rake rswag:specs:swaggerize
```

Never commit with a failing spec. Never skip or comment one out without fixing
the cause. Watch for a spec that was **pinning a bug in place** — when a fix
turns one red, the question is which of the two is right, and sometimes the
correct move is to update the expectation. Say so when it happens.

---

## Prove the suite can fail

**This is the first of the seven self-review questions and it is here because it
was violated five times in one day across this owner's other repos**: four
vacuously-green suites, a structural checker blind to its own blind spot, a lint
gate that only looked at `spec/`, another with 726 cops disabled, and a lint run
that silently skipped a whole cop family.

So, whenever you add a gate:

1. Plant the bug it is supposed to catch.
2. Watch it go **red**.
3. Remove the bug. Watch it go green.
4. Only then is the gate real.

A suite that reports 0 examples, 0 failures is a **failure**, not a pass. Check
the example count, not just the colour.

### And the harder version: CAN THE INSTRUMENT STILL SEE IT?

The four steps above test the **gate**. They say nothing about the **instrument**
the gate reads — and when the instrument is blind, a fix looks verified and is
not.

**Earned on F-21, 2026-09-16.** The claim to check was "the layout overflows the
right edge after a window narrows", measured at 2274 px by a previous session. I
measured it with `uiautomator dump`, applied the candidate fix, got **0 px**, and
was one step from reporting the bug fixed. Then I reverted the fix and measured
again — still **0 px**. The instrument reported 0 px in *every* condition,
including ones that are obviously broken to the eye, because **`uiautomator`
bounds are clipped to the window**. The fix was in fact useless; the screenshots
proved it broken with and without.

So for anything measured rather than asserted — a layout, a timing, a memory
figure, a rendered pixel:

1. **Put the bug back and check the instrument still reports it.** Not the gate:
   the *measurement*. If the number does not move, the number is not about the
   bug.
2. **Do that before trusting a green reading, not after.** A measurement taken
   only in the fixed state cannot be distinguished from a measurement of nothing.
3. **Say which instrument produced a number**, so the next person can question it
   rather than inherit it. F-21's original 2274 px is now of unknown provenance,
   which makes a real diagnosis harder to build on than a missing one.

**The general form:** "prove the gate can go red" protects you from a check that
cannot fail. This protects you from a check that cannot *see*. A bug needs an
instrument before it needs a hypothesis — and when three attempts at one bug have
all been reasoned rather than measured, the missing instrument IS the bug to work
on.

---

## A measurement taken on an EMPTY SUBJECT agrees with everything

The third shape of the same failure, and the one that hides best.

**Earned on F-21, 2026-09-17.** A script measured the left and right gutters of
a screenshot to decide whether a layout had overflowed. On a cold start that had
not finished rendering, it reported **"looks correct"** — because an unrendered
band is entirely background, so *both* gutters measured the full screen width and
the symmetry test passed. **A blank screen is the most symmetric screen there
is.**

That script existed specifically to avoid vacuous greens, and it had one built
in. So the rule is not "be careful with instruments" — it is a check you can
actually run:

> **Before trusting a measurement, ask what it returns when there is nothing to
> measure.** If the answer is "pass", the instrument cannot tell success from
> absence, and every green reading it has ever given is unverified.

Concretely, the guards worth adding:

- **An emptiness check that fails loudly.** The gutter script now reports
  `NO CONTENT in the band` when the two gutters sum to the full width, instead of
  a verdict it cannot support.
- **Wait for the SUBJECT, not for a timer.** Two readings in that session were
  taken during a Metro re-bundle and had to be discarded. The loop now waits for
  a known piece of real content and re-verifies it is still present *after* the
  capture.
- **A count assertion on any gate that iterates.** A suite reporting `0 examples`
  is a failure; so is a structural check that matched zero files, or a key-parity
  check that found zero keys. Assert the denominator.

### A passing suite that does not EXIT has not finished talking

The same family, one step further out. Sixteen tests passed in six seconds and
the Jest worker then sat for six hundred more. **The result agreed with me while
the instrument was lying about something else entirely** — a query had rejected,
`useLastKnown` retries once, and `client.clear()` drops the cache without
cancelling the timer.

`--detectOpenHandles` reported nothing, because a React Query retry is not a
handle Jest names. What found it was running each test **alone** and diffing
against `HEAD`: the two that hung were exactly the two whose queries rejected.

So: **a green run that does not return to the prompt is an unread result.** Do
not reach for `--forceExit` — that hides precisely the thing the hang is telling
you, which is that the code under test leaves work running after the assertion
passed. In an app that is a timer nobody cancels; in a test it is six hundred
seconds of somebody's afternoon.

### And there is a SECOND timer, in the mutation cache, that `clear()` cannot remove

Found on 17 Sept 2026 building the Profile screen, and worth writing down
because the obvious fix above is not enough and the reason is in the library
rather than in our code.

`cancelQueries()` + `clear()` was applied, and the suite still would not exit.
Only the tests that fired a **succeeding** mutation held the worker; the ones
that never reached the server were clean. Unmounting runs
`MutationObserver.onUnsubscribe` → `Mutation.removeObserver` →
`Removable.scheduleGc`, which installs a **300,000 ms** timeout, because
mutations default to a five-minute `gcTime`. And
`@tanstack/query-core/src/mutationCache.ts:190` — read it — deletes the entries
from its Map and notifies observers but **never calls `mutation.destroy()`**,
which is the only thing that clears that timer.

So `queryClient.clear()` cannot remove it. Calling `clear()` twice does not
either; both were tried and measured before the cause was understood.
`karwan-mobile/src/__tests__/queryTeardown.ts` is the three-line teardown every
suite with a `QueryClient` should call, and its header carries this reasoning.

**The technique is the transferable part, because `--detectOpenHandles` named
nothing here either.** Two steps, both cheap:

1. **Bisect by test**, not by suite. Run each `it` alone and see which ones
   hang. The pattern — "only the ones whose mutation succeeded" — was the whole
   diagnosis.
2. **Then ask the process what is still alive.** `process.getActiveResourcesInfo()`
   in an `afterAll` said `["PipeWrap","PipeWrap","Timeout","Timeout","Timeout"]`,
   which proved it was a timer and not a socket. Wrapping `global.setTimeout` to
   record `(delay, stack)` and printing the survivors then named the line
   exactly, with its 300000 ms delay and its call into `Mutation.scheduleGc`.

That second step took one edit and answered in one run, after two wrong
hypotheses had each cost a full suite run. **Reach for it before the third
guess, not after it.**

## THE SEVEN SHAPES OF A LYING INSTRUMENT

The first four came out of **one bug in one week** — F-21 — and every one was
caught by asking *what can this instrument see?* rather than *does it agree
with me?* They are worth learning as a set, because each one passes the checks
that catch the others.

The fifth, sixth and seventh were added on 17 Sept 2026 and are the three that
do not fit the table: the fifth reads **nothing** and is mistaken for a
reading; the sixth reads something **true** and is mistaken for evidence; the
seventh reads correctly today and **becomes wrong later**. The first two arrive
exactly when you are hunting a red, which is what makes them expensive. The
seventh is worse than expensive — it is the only one that is **undetectable by
looking**, because on the day it is written it works.

| | The failure | How it appeared |
|---|---|---|
| **1 · Clipped** | the instrument physically cannot observe the defect | `uiautomator` `bounds` are clipped to the window, so right-edge overflow read **0 px in every condition**, including screens that were visibly broken |
| **2 · Out of frame** | the instrument is fine; the SUBJECT is not where it looks | a planted bug positioned at `top: 700` **dp** while the measurement band was in **pixels** — it landed at px 1838, below the band, and the instrument read "correct" |
| **3 · Empty** | there is no subject at all | an unrendered screen passed a symmetry test, because both gutters measured the full width |
| **4 · Wrong subject** | there IS a subject, and it is the wrong one | a **splash screen** passed the gutter test with flying colours — a splash is perfectly symmetric |

### The question that finds each one

Shape 3 taught "ask what it returns when there is nothing to measure". Shape 4
showed that was not enough: **"is there content" was the wrong question, and
"is it the content I meant" is the right one.** A guard that only checks for
emptiness is satisfied by any screen at all.

So the working procedure, in order of what it costs:

1. **Put the bug back and check the measurement moves.** Catches shape 1.
2. **Locate the plant.** Confirm the thing you planted is where the instrument
   looks — units especially, dp against px being the classic. Catches shape 2.
3. **Ask what it says with no subject.** Catches shape 3.
4. **Assert the subject's IDENTITY, not just its presence**, and re-assert it
   *after* the capture. Catches shape 4. Concretely, what finally worked:
   dump → capture → dump again, requiring a known marker **both times**, so a
   reload between the two invalidates the pair and it retries.

**A green reading is evidence only when you know what red looks like, and that
the subject was present, and that it was the right subject.**

### Why this is not paranoia

Three fixes for F-21 were "verified" against instruments from this list before
one of them was caught. A wrong instrument does not merely fail to find the
bug — it manufactures agreement, and agreement is what stops you looking.

### THE HEADLINE PROPERTY IS THE ONE MOST LIKELY TO BE UNASSERTED

Because it is the thing you were **thinking about**, not the thing you were
**checking**. It is so present in your head while you write the code that it
does not feel like something anyone could fail to test — and so it is the one
nobody did.

**Three receipts from a single day, 2026-09-17:**

| Feature | What was asserted | What was NOT |
|---|---|---|
| the shortage multiplier | `delivery_fee - courier_fee == 0` — the platform keeps none of it | that the storm ever **arrived**. Deleting the whole feature left it green |
| the pending-migration 503 | the status, the JSON, the code, the remedy, the cache header | that it **named the migration** — the entire reason it exists |
| the distance top-up's ordering | that a top-up was written, with the right value | that it used the **post-assignment** fee. The first version compared two values the cap had clamped to the same number |

The pattern is the same each time: every assertion was about the *scaffolding*
around the property, and the property itself was assumed. And each was caught
by the same thing — **planting the bug and watching which example goes red**,
not by re-reading the spec.

**A CAP OR A CLAMP MAKES A PLANT SURVIVABLE**, and the third receipt is the
example. The ordering example compared the right answer against the wrong one
— but both were above the commission, so the cap clamped them to the same
number and the comparison was between two identical values. The plant ran, the
example stayed green, and the code was genuinely broken.

So: **an assertion downstream of a clamp has to be planted against a value the
clamp cannot reach.** Concretely, give the fixture enough headroom that the cap
does not bind, or assert on the pre-clamp quantity. Any `min`, `max`, `clamp`,
floor, ceiling or `||` default between the bug and the assertion is a place
where a wrong answer and a right one can arrive looking identical — which makes
it a place where the plant proves nothing while appearing to prove everything.

A fourth receipt from the same afternoon, different shape and the same lesson:
**the code was right and the test was wrong.** An example expected 50 and got
30.06; the instinct was to correct the expectation. The instrument said the
courier's fee was 170 rather than the fixture's 100, because assignment
re-freezes it from the courier's vehicle rate. A failing test feels like news
about the code, and that is the direction almost nobody checks.

So, before a feature is done, ask it in one sentence: *what is the one thing
this exists to do?* Then find the example that goes red when that one thing is
removed. If there is not one, the feature is untested however many examples
are green.

### A TEST THAT STATES WHAT IT CANNOT SEE IS WORTH MORE THAN ONE THAT IMPLIES IT SEES EVERYTHING

`spec/services/pricing/money_conservation_spec.rb` asserts an accounting
identity over a matrix of tiers, storms, distances and baskets. It is the
strongest gate in the money model and **it has a hard limit that has to be
written down, because a green conservation suite reads as "the money model is
correct" and it does not mean that.**

> **Conservation catches money appearing or vanishing. It does NOT catch the
> wrong party being paid**, because re-attribution conserves perfectly.

The live bug in that file is the proof: the premium uplift is charged to the
customer and kept by the courier instead of the platform. Every afghani is
accounted for, nothing appears or vanishes, and **conservation is satisfied by
the defect.** That is why the file asserts a second, separate thing —
*attribution*, `intended` versus `actual` per party — and why the leak lives in
that half.

**Two shapes came out of building it, both worth the rule:**

**1 · A RESIDUAL CANNOT FAIL.** The first version defined the courier's share
as `customer_total - merchant_payout - commission`, which sums to
`customer_total` by arithmetic. 101 examples, in a file whose entire purpose is
to fail, that could not. Caught by planting a leak and finding nothing went red
— never by reading it. Rebuilt from independent stored fields, the same plant
turns 50 of 126 red.

**Any quantity defined as "everything that is left" is an identity, not a
measurement.** If one term of a sum is computed by subtracting the others from
the total, asserting the sum proves only that subtraction works.

**2 · Say the limit in the file.** The next person to read a green suite should
learn what it did not check from the suite itself, not from whoever wrote it.

**3 · TEST THE SURFACE THE PERSON TOUCHES, NOT THE ONE THE CODE EXPOSES.** The
config audit asserted that every setting could be PATCHed — and
`Admin::SettingsController#update` permits `:value` itself, so the PATCH
succeeds whatever the console renders. Emptying `SettingDashboard::FORM_ATTRIBUTES`
left **every example green while the edit page had no input to type in.** The
file's own header describes that exact failure — "a row that exists but is
absent from the dashboard's form is as untunable as one that does not exist" —
and the file did not test it.

The fix was to assert the page he opens (`GET .../edit` contains
`setting[value]`) rather than the request a test can make. **An API a human
never calls is not the surface; the form is.** Ask what the person actually
does, and drive that.

### THE EIGHTH SHAPE: A PERFECT INSTRUMENT POINTED AT SOMEBODY ELSE'S DOMAIN

> **Two receipts from 2026-09-18, and the second says the shape is not confined
> to tests.** The pattern in one line: **ask what chose the domain.** If the
> answer is "whoever wrote it", the instrument covers the author's memory rather
> than the subject, and the gap is invisible from inside.
>
> **It appeared INSIDE the instrument built to find it.** The negation sweep
> read 37 assertions and hardened 13, and it found them by grepping
> `not_to include`. Four tenancy checks written as `to be_empty` or `be_nil`
> were never looked at — the same weakness in a different matcher. **The
> sweep's domain was chosen by the MATCHER rather than by the claim**, so it
> reported a clean result over a subset it had picked without saying so.
>
> **And once in production code, where it cost more.**
> `Search::Transliteration::LETTERS` claims to romanise Pashto and Dari. It had
> `ک`, `ك` and `گ` and no `ګ` — the Pashto gaf — because the table's domain was
> whatever its author typed, not the alphabet. An unmapped letter is silently
> dropped, so `ننګرهار` indexed as "nnrhar" and Nangarhar was unfindable. Four
> letters were missing, one of them used by our own dictionary.
>
> **The fix that generalises is the same in both cases: give the instrument a
> domain that exists independently of it.** The authorisation sweep derives its
> routes from the class hierarchy; the letter gate iterates the alphabet and
> fails on any letter the table cannot read. Adding four keys would have fixed
> today and left the next forgotten letter exactly as invisible.

The other seven describe an instrument that is wrong. **This one has no defect
at all** — it reads correctly, reports completely, and is honest about
everything it covers. Its scope was simply inherited from an unrelated artifact,
and nobody chose it.

**The receipt is a ZERO, which is what makes it the hardest to see.** Catalogued
every deprecation the app would die on at the next Rails upgrade by running the
full suite with stderr captured. **Before the operator spec existed, that run
emitted zero** — and a zero reads as *"the app is ready for 8.2"*.

It was not. `Administrate::Search` calls `term.mb_chars`, removed in Rails 8.2,
on the thousand-times-a-day path of the surface Hamma9900 says matters most.
**Nothing was broken and nothing was lying. Nothing drove the code.**

> **A catalogue built from a test suite inherits the suite's blind spots
> exactly.** So the answer is to widen coverage, not to re-run.

**How it differs from its neighbours**, because the distinction is the whole
value:

| | The instrument |
|---|---|
| shapes 1–4 | observes the wrong thing, or nothing, or the wrong subject |
| fifth | reads **nothing** and is mistaken for a reading |
| sixth | reads something **true** and is mistaken for evidence |
| seventh | is **right today** and wrong on a date nobody chose |
| **eighth** | is **correct and complete over a domain somebody else chose** |

**The question it earns**, alongside *is the subject there* and *could this have
moved*: **what is this measuring over, who decided that, and what lives outside
it?** For anything derived from a suite — coverage, deprecations, a dependency
audit, a performance profile — the honest report states the bound in the same
breath as the number. *"One deprecation"* is a different claim from *"one
deprecation on the paths the suite covers"*, and only the second is true.

The floor it produced: `spec/requests/admin/every_console_page_opens_spec.rb`,
which drives index, search and show for every routed console resource — because
the reason search was dark is that nothing opened the ordinary pages.

### WHEN NOT TO BUILD A GATE: IT MUST NOT FIRE ON CORRECT CODE

The eight shapes are about instruments that mislead. This is the condition under
which **building one is the wrong move at all.**

A gate that goes red on code that is fine does not get fixed. **It gets
silenced** — and a disabled gate is worse than no gate, because it leaves a
*reason to believe* behind it. Everybody remembers there is a check; nobody
remembers it is off.

Measured here. A heuristic for the rule below — *"a `not_to include(X)` with no
`to include(X)` in the same file"* — flags **38** assertions, and **most are
correct by design**: `not_to include("updated_at")` on a column list is a real
fact about the schema, and a column list is never empty. Shipping that heuristic
as a gate would have failed the legitimate majority on every run and been
deleted within a week.

**So it stayed a sweep and the judgements were written into the files instead**
— a trailing `# by-design:` comment on each legitimate negative, so the next
sweep reads only the unmarked ones. **A judgement pass that must be repeated
from scratch is a judgement pass that will not be.**

The test: *would this gate ever be red while the code is right?* If yes, it is a
sweep with its results recorded, not a gate.

### A NEGATIVE ASSERTION NEEDS ITS POSITIVE SHOWN FIRST

**"X is absent" proves nothing unless X could have been present.** Otherwise it
is the fifth shape wearing a negation: a green with no subject, and the
assertion passes for a reason that has nothing to do with the behaviour.

Found in this repo on 2026-09-17, in a file written the same day:

```ruby
delete "/admin/merchants/#{merchant.id}"
expect(Merchant.listed).not_to include(merchant)   # passes if `listed` is empty
```

A broken `listed` scope passes that exactly as a working discard does. The fix
is one line above the action:

```ruby
expect(Merchant.listed).to include(merchant), "not listed to begin with — the check below is vacuous"
```

**The general form**, which came from the rig finding the same shape in a
Maestro flow — `assertNotVisible: route-marker-courier` on a screen where **no
marker is ever in the tree**, so the flow's central claim asserted nothing:

> Every "this is absent" needs a paired case where that same subject **does**
> appear. If nobody has demonstrated the positive, the negative is decoration.

**A cheap sweep for it**, since the suite has 240 negative assertions:

```
# not_to include(X) where nothing in the same file ever asserts X present
```

Most hits are legitimate — `not_to include("updated_at")` in an audit-values
test is a subject that must never appear by design. The ones worth reading are
where the SUBJECT ITSELF might never exist: a scope that could be empty, a
record that might not have been created, an element never rendered.

#### The loophole that reads like the positive: `expect(collection).to all(...)`

`all` is the matcher most likely to be mistaken for the paired positive it is
standing in for, because it *reads* as one:

```ruby
expect(entries).to all(have_key("currency"))     # green on `[]`
```

**`all` is vacuously true on an empty collection.** It asserts "nothing in here
violates the rule", and nothing violates a rule in an empty room. So a sweep
written as `expect(everything).to all(be_correct)` reports green in exactly the
two cases worth knowing about: the scope broke, or the fixture never built.

This is not matcher trivia — it is the fifth shape (a measurement that never
ran) in the one syntax that looks like a measurement of everything. The same
holds for `none`, `all(be_valid)` over a `where` that returns nothing, and any
`each` loop whose body contains the only expectations in the example.

**The rule:** an `all` needs the room proved non-empty on the line above — a
count where you know it, `not_to be_empty` where you do not.

```ruby
expect(entries).not_to be_empty, "no entries — the assertion below is vacuous"
expect(entries).to all(have_key("currency"))
```

**A guard that fails on empty already counts**, and most legitimate uses have
one without meaning to: `expect(sources.uniq).to eq(["osrm"])` on the line above
cannot pass on `[]`, so the `all` beneath it is covered. The sweep for this shape
found 14 `all` matchers in this suite, **4 already guarded that way, 5 genuinely
vacuous, 2 in another session's file, and 3 false positives** — including
`all(be_present)` over a four-element array literal, which can never be empty.
Read each one; do not patch on the grep.

The derived specs in this repo do this deliberately — `bin/gates`'s listing spec
compares against a count taken from the filesystem, and the authorisation sweep
opens with "found the routes to sweep" — because a route-derived example group
that derives **zero** routes is a green suite asserting nothing at all.

#### THE UMBRELLA: AN ASSERTION KEYED ON SOMETHING THE SUBJECT ITSELF CONTROLS

Three instances in three days, in three languages, and they are one defect:

| Keyed on | What else produced it | Found in |
|---|---|---|
| an **amount** (`include(500.0)`) | another courier's ledger row | `wallet_spec` |
| a **substring** (`assertVisible: "کور"`) | the flow's own previous run, appending | a Maestro flow |
| a **clock** (`Time.zone.parse("01:00")`) | the app's own `config.time_zone` | `today_figures_spec` |

> **If the thing under test can produce, extend or move the value you match on,
> the assertion agrees with it instead of checking it.**

Each looks like a normal assertion and each is green for the wrong reason. The
question that finds all three: **who else can produce this value — and is one of
them the subject?** Yesterday's run of the same test counts. So does the
framework the subject is configured by.

The remedy is the same in each language: key on something the subject does not
control. A row's **id**. An **equality** rather than a containment. A **fixed
point on the clock** rather than one the app resolves.

The three sections below are that rule in its three languages; read them as one.

#### AND THE SUBJECT MUST BE AN IDENTITY, NOT A VALUE SOMEBODY ELSE CAN PRODUCE

A paired positive fixes the empty-room problem. It does **not** fix a positive
that the wrong row can satisfy.

Found on the evening of 2026-09-17, in an example hardened that same morning:

```ruby
amounts = json["wallet_entries"].map { |e| e["amount"].to_f }
expect(amounts).to include(500.0)          # whose 500?
expect(amounts).not_to include(777.0)      # whose 777?
```

Both halves are keyed on an **amount**, and an amount is not a name. A seed, a
factory default, or another session writing into the same fixture from the other
end can produce 500 or 777 — satisfying the positive without the subject's own
row being present, or contradicting the exclusion without anything having
leaked. It failed once under `config.order = :random`, passed on every rerun,
and the mechanism was never proven because the seed was not captured.

```ruby
ids = json["wallet_entries"].map { |e| e["id"] }
expect(ids).to include(mine.id)
expect(ids).not_to include(theirs.id)
```

> A tenancy assertion keyed on a value is answering "is a row like this one
> here?" when the question is "is *this row* here?"

#### THE SAME DEFECT IN ANOTHER LANGUAGE: A SUBSTRING ASSERTION CANNOT DETECT A SUBSTRING BUG

Found by the mobile session on 2026-09-18, in a Maestro flow, and it is this
rule one layer up rather than a separate lesson.

A flow renamed a saved address with `inputText: " نوی"`, which **appends** to a
pre-filled field rather than replacing it — and the value persists in the
database. So each run compounded: `کور` → `کور نوی` → `کور نوی نوی`. The flow
was green exactly once per reseed, by construction.

What makes it a shape rather than a bug is the check. It asserted
`assertVisible: "کور"`, and **`کور` is a prefix of `کور نوی`**. So no assertion
in that flow could ever have detected the corruption the flow itself was
causing. The write and the read shared one oversight.

> The assertion was not weak. It was **incapable** — aimed at a bug it could not
> express — and it would have stayed green while the data rotted.

**The rule:** a prefix, a `contains`, an `include` or a SQL `LIKE` cannot
distinguish the correct value from *the correct value plus anything*. Where a
test both WRITES and READS a value, the read is keyed on equality or on
identity, never on containment.

**And it is the same defect as the wallet example above**, in a different
language: an assertion keyed on a value that another writer can also produce.
There the other writer was a second courier's row; here it was the flow's own
previous run. When you find one of these, ask who else can produce the value
you are matching on — and remember that "yesterday's version of this same test"
is one of the candidates.

#### AND THE THIRD LANGUAGE: AN EXAMPLE EXPRESSED IN THE ZONE UNDER TEST

`config.time_zone` was never set, so every "today" in this app meant the UTC day
— 04:30 to 04:30 in Kabul. The spec written to pin that down said:

```ruby
travel_to(Time.zone.parse("2026-09-18 01:00")) do   # moves WITH the app
```

**It passed under UTC too.** `Time.zone.parse` resolves in whatever zone the app
is configured with, so the instant moved when the configuration moved, and the
only thing catching a reversion was a separate assertion on `Time.zone.name` —
a config check standing in for a behaviour check.

> **An example that expresses its instants in the zone under test cannot detect
> a change to that zone.**

Rewritten against fixed points — `Time.utc(2026, 9, 17, 21, 30)` is 02:00 Kabul,
`Time.utc(2026, 9, 18, 0, 30)` is 05:00 the same morning — it fails on its own.
The re-plant is the proof: reverting the zone went from **one** failure to
**two**, and the second one is behaviour rather than configuration.

**The general form, beyond clocks:** any example whose fixture is derived
through the same setting it is testing is checking that the setting agrees with
itself. Locale, currency, rounding mode and page size all have this shape.

**And note which direction the lesson runs.** That example was one of the two
vacuous assertions found by the negation sweep hours earlier. **A vacuous
assertion cannot have an order dependency — it passes regardless.** Hardening it
is what gave it the capacity to fail, and the failure is the first thing in the
suite to notice that two sessions were writing into one fixture from opposite
ends. An instrument that starts failing after you sharpen it is the instrument
working.

### A CONSTANT IN AN `RSpec.describe` BLOCK IS GLOBAL

`ROUTED = ...` written inside `RSpec.describe` is **not scoped to the example
group.** Ruby assigns it on `Object`, so it is a top-level constant shared by
every spec file in the run.

Measured 2026-09-17. Two spec files each derived a list from the router and each
called it `ROUTED` — one the custom admin ACTIONS, one the routed console
RESOURCES. **Both passed alone. In a full suite they collided**: whichever
loaded second won, and the first file's examples then asserted against a list
built to answer a different question. The failure message was bizarre — a
resource-coverage example complaining about `admin/orders#reassign`.

> **Green in isolation, wrong together, and invisible unless the whole suite
> runs** — the same shape as two sessions sharing a test database, arriving
> through the language instead of the box.

Two consequences worth keeping:

- **Name a constant in a spec for the question it answers**, not for the
  concept — `CONSOLE_RESOURCES`, not `ROUTED`. A generic name is a name
  somebody else will pick.
- **A targeted run cannot see this class of bug at all.** It is the argument
  for running the whole suite before committing, and the reason a passing file
  is not a passing change.

### WHEN A FAILURE LOOKS LIKE ANOTHER SESSION'S, RUN IT BOTH WAYS FIRST

**Revert your change, run the example, restore it, run it again.** Ninety
seconds, and it is cheaper than the message you were about to send — and far
cheaper than the hour the other session spends hunting a bug in its own work
that you planted.

Earned on 2026-09-17. A seed change of mine broke `spec/seeds/e2e_spec.rb`, and
every piece of circumstantial evidence pointed away from me: that file and its
spec were **uncommitted in the other session's working tree**, and the last
commit touching either was **theirs**. The message was drafted.

Run both ways, it passed without my file and failed with it. The mechanism was
invisible in both diffs: `e2e.rb` resolves its approver with
`find_or_create_by!(email: "ops@karwan.af")`, found the account my seed had
just created, and **skipped its own block** — so their fixture quietly lost the
attributes it depended on.

**The trap is that the story was TIDY.** Uncommitted files, their commit, their
area — an explanation that accounts for everything is exactly when nobody spends
the ninety seconds. Every confident wrong attribution has that shape, including
the four corrected in the other direction the same day.

> Circumstantial evidence about **who** is not evidence about **what**. The repo
> can answer the second question exactly, and the answer is cheap.

### "IS THIS USED OUTSIDE ITS CLASS" IS A VISIBILITY QUESTION AND READS AS REACHABILITY

The two look identical in a grep and answer different things. Confusing them
produces a confident report that a working safeguard is dead.

Measured on 2026-09-18 while sweeping for methods nothing calls. The sweep
excluded each method's own defining file — reasonable, if the question is
*"does anything outside this class use it?"* Under that reading
`OtpVerification.send_allowance` came back unreferenced, and it is **the OTP
send throttle**, which correction 6 makes a BILLING control rather than only a
security one. It is called by `issue!` eleven lines below its own definition:

```ruby
def self.issue!(phone)
  allowance = send_allowance(phone)          # <- eleven lines below
  raise Throttled, allowance[:retry_after_seconds] unless allowance[:allowed]
```

> A method used only inside its own class is **over-public**, not unreachable.
> One is a tidiness observation; the other is "somebody spends Hamma9900's
> money".

**So state which question the instrument answers, in the instrument.** Same run,
same tool, two more ways to get the domain wrong: `\b` does not anchor after
`?` or `!`, so every predicate and bang method looked unreferenced — 119 false
positives including a method called from a controller written an hour earlier.

**And validate a sweep against a bug you already know.** `Merchant.fuzzy` was a
confirmed unreachable method that morning: unwiring it made it appear with 11
spec refs, wiring it made it vanish. A sweep that cannot find the case that
motivated it is not ready to report on cases nobody has checked.

### A SUBSET THAT COVERS THE FILES YOU TOUCHED IS NOT THE SUITE

The obvious way to run less is to run the directory you edited. It is also the
way to miss a failure in a file you have never opened — because **what your
change breaks is not decided by where you made it.**

Measured on 2026-09-18. Two fields were added to `UserDashboard`:
`live_session_count` and `registered_devices_summary`, both **computed methods**
rather than columns. `spec/requests/admin/` was **green**, 411 examples. The
full suite was not:

```
PG::UndefinedColumn: column users.registered_devices_summary does not exist
```

Administrate builds its search as a SQL `LIKE` over **every string attribute a
dashboard declares**. So declaring a method broke `/admin/users?search=…` — a
query in code I did not write, exercised by examples in files I did not open,
in the same directory I had just run green. The fix was one option
(`searchable: false`); the lesson is that I could not have predicted which
directory to run, because **the framework chose the blast radius, not me.**

> That is the eighth shape from the other end. Usually an instrument is correct
> over a domain somebody else chose. Here the *test run* was correct over a
> domain a **framework** chose — and the domain that mattered was "every query
> Administrate generates from a dashboard constant".

**The rule:** run the full suite before you commit. Not because subsets are
wrong to use while iterating — they are the only sane way to work — but because
the green they produce is a statement about the subset, and the commit message
is a statement about the suite. When those two disagree, the commit message is
the one people believe.

**And when a subset and the suite disagree, that gap is itself the finding.**
Ask what connected the file you changed to the file that broke. Here it was a
framework reading a constant; elsewhere it has been a shared constant landing on
`Object`, a seed committed by another session, and a stored column nothing
rebuilds. Each of those is invisible from inside the directory you edited.

### A CHECK NOBODY RUNS IS INDISTINGUISHABLE FROM A CHECK NOBODY WROTE

The five shapes are about instruments that **lie**. This one is about an
instrument that is **correct and never read**, which costs exactly as much and
is harder to see, because every audit of the code finds it present and right.

**This repo has now paid for it four times.**

| | The check | Why it never fired |
|---|---|---|
| `OrderPolicy#track?` | written, correct, complete | nothing called it — the customer's map had no data source and the policy spec did not notice, because a request spec proves the endpoints that exist and says nothing about a predicate nothing calls |
| edu-safi's tenancy scope | the correct scope existed | five endpoints never consulted it; `current_organization` is tenancy, not permission |
| two role-gate methods | looked like the gate | no callers at all. Deleted rather than tested — a gate with no caller is not a gate |
| **`bin/preflight:58`** | `needs_migration?`, hard-failing, with a scar in its own comment | **nobody ran preflight between generating a migration and the API being hit**, so the shared development API 500ed for every session on this box |

The fourth is the instructive one, because the check was not merely present —
it was *good*. It fails closed, it asks Rails rather than `psql`, and its
comment records a previous bug in itself. None of that mattered for one hour of
three sessions' time.

**A THIRD INSTANCE, 2026-09-17, in a different costume.**
`spec/requests/admin/config_reachability_spec.rb` proves every one of the 42
`Setting` definitions materialises as a row Hamma9900 can edit. It is a good
check and it passes. **It does not prove anybody runs the seed** — and
`config/deploy.yml` puts `db:seed` under `aliases:`, a shortcut a person types,
with no `.kamal/hooks/` anywhere. So the code is proven and the deploy does not
call it, and the symptom would be a Config screen that is merely *short*, on an
app that works perfectly on defaults nobody can see.

**So a check earns its place only with a trigger**, and "somebody will run it"
is not one. A trigger is CI, a git hook, a pre-deploy step, a startup
assertion, or a failure the system produces by itself at the moment of the
mistake. When you add a check, write down what runs it — and if the answer is a
person remembering, you have written a docstring with an `if` in it.

The corollary that applies to everything in this file: **before adding a check,
look for the one that already exists.** Today's fix was very nearly a second
copy of a working check, which would have left two checks nobody runs.

### AN ASSERTION ON A DIFFERENCE IS SATISFIED BY BOTH SIDES BEING UNMOVED

Not a fifth shape — a sharper form of the rule the four already serve, and it
cost a real example on 2026-09-17.

The shortage multiplier's whole justification is that **the platform keeps none
of the uplift**: the customer pays more because the courier is paid more. That
was asserted as

```ruby
expect(amounts[:delivery_fee] - amounts[:courier_fee]).to eq(0)
```

which is true when both sides rose together — **and equally true when neither
moved at all**, because the customer's fee is derived from the courier's.
Planting `courier_fee = base_delivery_fee`, which deletes the entire feature,
left it green.

**Zero-on-both-sides is what deleting a feature looks like.** So any assertion
shaped like `a - b == 0`, `a == b`, `ratio == 1` or "nothing leaked" needs a
second one saying **the pair is not at rest**:

```ruby
expect(amounts[:delivery_fee]).to be > calm[:delivery_fee]   # the storm arrived
expect(amounts[:delivery_fee] - amounts[:courier_fee]).to eq(0)  # we kept none of it
```

The uncomfortable part, and the reason this is here rather than in a code
comment: it was written by somebody who had finished documenting *a check that
cannot fail is worse than no check* an hour earlier, in this file. **The rule
cannot be followed by remembering it — only by executing the plant.** That is
what the plant step is for, and it is why "I checked carefully" is not a
substitute for it.

### The fifth shape: THE MEASUREMENT THAT NEVER RAN

The four above all read something and read it wrongly. This one reads
**nothing**, and gets mistaken for a reading — which makes it among the
cheapest of the six to fall for, because it turns up at the exact moment you
are looking for a red.

Measured here on **2026-09-17**. Two sessions were running suites against the
same test database. A deliberately planted bug came back as:

```
0 examples, 0 failures, 1 error occurred outside of examples
   ERROR:  deadlock detected
   DETAIL:  ... database_cleaner ... truncate_tables
```

The plant WAS correct and the gate WAS real — but that output proves neither.
It is not a pass and it is not a fail. **Read as a red it would have "proved" a
gate that never ran**, which is precisely the claim the plant exists to
establish, arrived at without evidence.

### The sixth shape: A VALUE THAT CANNOT BE WRONG

Added 17 Sept 2026, from F-21's widening question, and it is the subtlest of
the set because the reading is **true**. It is not "reads nothing", and it is
not "wrong subject" — it is an accurate measurement of the wrong quantity.

The question was whether the app's layout handles the window GROWING, or
whether it is broken and merely invisible. The instrument: read the widest
node's pixel width out of a uiautomator dump in each of six states.

It returned **1080px in all six — including the state already known to be
broken.** A red-proof case coming back green.

The cause: the app's root is a `flex: 1` container, so it **always** lays out
at the window width whatever the app believes its own dp width to be. A stale
reported width harms components that SIZE THEMSELVES from it, never the root.
Every one of those 1080s was correct. They were also silent about the defect,
because the quantity was correct **by construction** — no possible state of the
bug could have moved it.

**The tell, and it is the same tell as the other five: the case that should
have gone red did not.** The protocol saves you here if you follow it — state
the measurement and the state that must make it fail BEFORE forming a
hypothesis, then check that state actually fails. A green from an instrument
whose red case has never fired is not evidence.

**What worked instead: measure the disagreement, not one side of it.** F-21 IS
`useWindowDimensions()` and the real layout width differing, so the instrument
became a probe rendering BOTH numbers and their delta. A non-zero delta is the
bug and its SIGN says which direction is broken — so it can go red in either
direction, which was the whole question. It then went red twice in the same run
(both shrink states, +20.57dp) and zero twice (both widen states), and those
zeros mean something precisely because the reds happened beside them.

**The question to ask of any instrument, before trusting a green:** *could this
number have moved at all if the bug were present?* If the answer is no, you
have measured something true and learned nothing.

### The seventh shape: A TIME-DECAYING SUBJECT

The first four lie **now**. The fifth reads nothing. The sixth reads something
that cannot be wrong. **This one is honest on the day it is written and becomes
a liar on a date nobody chose.**

Found while seeding a pending offer so that `courier_offer.json` — which was
`{"offer": null}` — became a real subject at all.

`Offer.pending` is `status_offered.where(expires_at: Time.current..)`. When the
seeded offer expires, `GET /courier/offer` answers `{"offer": null}` again. A
test asserting a populated offer then **fails**, which is fine. The danger is
the version that does not fail: a test written against the null path, or a
fixture re-captured after expiry. Either one **silently restores the exact
empty subject the work existed to remove** — and the empty subject is shape one
on this list. The fixture does not merely go stale. **It rots back into
vacuousness, with nothing red.**

**Why only a plant finds it, and this is what separates it from the other
six:** *on the day you write it, it works.* Every assertion passes, the payload
is populated, the suite is green. The decay is in the future, so no amount of
care at the time of writing detects it — the other six all yield to somebody
looking properly, and this one is **undetectable by looking**, at the moment of
writing, by the person best placed to see it. By the time it decays, whoever
reads the green did not write it.

**The three questions for any fixture. The third is the new one.**

1. Is the subject there at all? *(shape one)*
2. Could the number I am reading have moved if the bug were present?
   *(shape six)*
3. **Will this subject still exist next month, and what does the suite say on
   the day it does not?**

**What to do, in order of preference:**

- **Prefer a subject that cannot expire.** An order, an address, a catalog item
  are permanent rows. An offer, a session, a countdown, a signed URL, a token
  and anything carrying `expires_at` are not.
- **Where the domain requires expiry — and here it does, a 60-second dispatch
  deadline is the product — make the window generous for a human** (the seed
  uses 30 minutes) **and say in the runbook that the capture happens inside
  it.** `karwan-mobile/qa/CONTRACT_FIXTURES.md` does.
- **ASSERT THE LIVENESS, NOT THE PRESENCE.** This is the whole finding in one
  line, usable by somebody who reads nothing else: `offer.present?` passes an
  expired offer and `expires_at > Time.current` does not. `spec/seeds/e2e_spec.rb`
  asserts the latter, and the plant that proves it — seed an already-expired
  offer — fails 3 examples. Presence alone passes it.

### The near-miss beside it: A DIAGNOSIS THAT READS AS TRUTH

Recorded next to the seventh shape because they are **the same lesson from
opposite ends**, and neither yields to care.

Another session concluded a spec failure was another's work: the file sat
uncommitted in that tree, and the last commit touching it was theirs.
**Circumstantially perfect, and factually wrong.** It was composing the message
when it ran the example both ways — and its own seed's `find_or_create_by!` had
created the account the spec's setup then found and skipped. **Invisible in both
diffs.**

- The seventh shape is **a test that decays into a lie.**
- This is **a diagnosis that arrives already sounding true.**

A wrong diagnosis that *looks* wrong gets checked. One assembled from real
evidence, pointing at a real person's real uncommitted file, does not — it gets
sent. **Both yield to exactly one thing: running it twice.** Not reading it
again, not reasoning about it more carefully. Running it.

#### THE BOUNDARY, because this rule was handed over unbounded

*Running it twice* settles **whether your change caused a failure.** It does
**not** settle **whether a failure is real.**

`spec/spec_helper.rb` sets `config.order = :random`, so a second full run is a
**different experiment, not a repeat of the first** — a different permutation,
with different state reaching each example. A green on the retry therefore
means "not reproducible under this permutation", which is a much weaker claim
than "not a bug".

It cost a real result the same afternoon the rule was written.
`couriers/wallet_spec.rb:182` — *"never shows another courier's entries"* —
failed one full run and passed three later ones, including a full 1849/0. Under
`--order defined` that would have been a fix confirmed. Under random order it is
an **order dependency that is still there**, and the retry hid it.

**So, for a failure you did not expect:**

1. **Capture the seed before anything else.** RSpec prints
   `Randomized with seed NNNN` and it is the only route back to the
   permutation. Losing it — which I did — makes the failure unreachable.

   **This no longer depends on anybody remembering.** RSpec prints the seed
   only in the SUMMARY, which is exactly when it is least likely to survive: a
   run killed by the OOM killer never reaches the summary, and this box runs
   several sessions against one RAM budget. `spec/rails_helper.rb` now
   announces it **before the first example** as well, and appends
   `timestamp / seed / TEST_DB_SUFFIX / scope` to `tmp/rspec-seeds.log`, which
   outlives the terminal. One line at the top costs nothing; not having it cost
   an evening.
2. **`--seed NNNN --bisect`** reduces it to the minimal pair of examples.
3. **Only then re-run**, and re-run with that seed, so the second run is
   actually the same experiment.

**The general form:** a repeat is only a repeat if the conditions are held. If
anything between the two runs is randomised, generated, timestamped or shared
with another session, the second run answers a different question — and
`docs/NOTES.md` records this instance so nobody re-derives it.

### THE RULE — one test database per session

**Binding, not a tip.** When more than one session is up on this box:

1. **Each session exports its own `TEST_DB_SUFFIX` before running anything.**
   `config/database.yml` appends it to `karwan_test`, and it **defaults to
   empty**, so a lone session and CI behave exactly as they always have. Create
   yours once with `TEST_DB_SUFFIX=_xx RAILS_ENV=test bin/rails db:prepare`.
   Suffixes are handed out by Hamma9901 so two sessions cannot pick the same;
   this session holds **`_99`**.
2. **A run that reports zero examples is reported as an ERROR** — never as a
   pass, never as a fail, and never as a plant confirmed. Re-run it on your own
   database and believe the second result.

   **AND THE COLLISION DAMAGES BOTH RUNS, NOT ONLY THE ONE THAT REPORTS ZERO.**
   Learned the hard way on 2026-09-17, after this rule was already written:
   starting a small plant run while a full suite was still in flight — both on
   `karwan_test_99`, both mine — gave the plant the familiar `0 examples, 1
   error` deadlock **and gave the full suite one unrelated failing example**, in
   an auth spec nothing had touched. The zero-example run announces itself; the
   other one just looks like a regression, and costs an hour of bisecting a bug
   that does not exist.

   **THE SUITE NOW REFUSES, so this is no longer a rule to remember.**
   `spec/rails_helper.rb` takes a Postgres advisory lock keyed on the database
   name before anything can truncate, and a second process exits **1** with a
   message naming the database. A rule has to be recalled at the exact moment
   somebody is mid-hunt and wants one quick targeted run — which is when it
   will not be. A lock does not.

   Two details worth keeping, both found by testing it rather than reasoning:

   - **It is taken BEFORE the support glob.** `spec/support/database_cleaner.rb`
     registers a `before(:suite)` that truncates; hooks run in registration
     order and sorted alphabetically it would load first. The truncation is the
     destructive act, so the lock has to precede it.
   - **`exit!`, not `abort`.** `abort` raises SystemExit, RSpec's
     `before(:suite)` swallows it, and the run then reports
     `0 examples, 0 failures` and exits **0** — a refusal that looks like a
     pass, which is the exact shape the guard exists to prevent. The first
     version did precisely that.

   The boundary is per **process**, not per session: the measured failure was
   one session colliding with itself, so `TEST_DB_SUFFIX` alone never reached
   it.

   The diagnosis that settles it, for next time: a failure that **does not
   reproduce in any subsequent run** and appeared while another process shared
   the database is the collision, not a flake in the code. Three clean full runs
   afterwards is what confirmed it here.
3. **A count is part of a green claim.** "0 failures" without the example count
   beside it is not a result, which is why every commit message here carries
   the number. `1,523 examples, 0 failures` says something; `0 failures` says
   nothing at all.

**Why a suffix rather than a lock:** a lock makes the sessions wait on each
other, and the one thing worse than a slow suite is a suite people stop running.
This costs one environment variable and gives each session an instrument nobody
else can move.

---

## When a comment and the code disagree, believe neither — run it

A near-miss worth the same discipline, from the same session. A test asserted
that a component sets no `textAlign`; planting `textAlign: "left"` left it
**green**. Two explanations fit: the module was stale, or that key specifically
was being dropped.

Guessing would have picked one. What settled it was adding a **second, unrelated
property** — `opacity: 0.42` — right beside the plant and re-running: the opacity
appeared in the rendered output and the alignment did not. The module was fine;
React Native lifts `textAlign` out of `style` into a top-level prop, so the
assertion could never have failed.

**The technique generalises:** when a plant does not land, add a change you are
*certain* would show up next to it. It separates "my edit never arrived" from
"this specific thing is invisible to my check" in one run, instead of a sequence
of guesses.

---

## Layers, and what each one is honest about

| Layer | Tool | What a green result actually proves | Status |
|---|---|---|---|
| Model / unit | RSpec | the object behaves in isolation | **now** |
| Request | RSpec + rswag | the endpoint returns that payload with that status | **now** |
| Policy | RSpec | the predicate is right — **not** that anything calls it | **now** |
| Serializer | RSpec / request | those keys are in the JSON | **now** |
| Service | RSpec | the multi-step operation and its rollback | **now** |
| Mobile E2E | Maestro | the feature works on a device | **later** — see below |
| QA sweep | the `qa-sweep` skill + a rig | the screens are not just present but right | **later** |

### A SERIALIZER FIELD INSIDE A `view` IS NOT PROVEN BY A MODEL ASSERTION

The layer you assert at IS the claim you are making, and one line separates a
real verification from a green that says nothing about the screen.

Verifying `AFGHAN_UX.md` §6 — the courier's number reaching the customer's
status screen — the obvious assertion was the model:

```ruby
expect(order.courier).to be_present           # true, and proves nothing
```

`Customers::OrderSerializer` puts `courier` **inside `view :detailed`**. A
`view :list` render does not carry it. So the model assertion passes on a
record whose customer-facing payload is missing the field entirely, and the
screen gets nothing. What the screen reads is the serializer, so that is where
the claim belongs:

```ruby
rendered = Customers::OrderSerializer.render_as_hash(order, view: :detailed)
expect(rendered[:courier][:phone]).to eq("+93700000803")
expect(rendered[:courier][:name]).to eq("QA")     # first name only, by design
```

**This is the same family as CLAUDE.md's *"a typed `http.get<T>` is a cast, not
a validation"*** — there the type agreed with the code while the code was
wrong; here the model agrees with the intent while the payload is empty. Both
are an assertion made one layer away from the thing that matters, and both
produce a confident green.

**The rule:** assert a serializer's output through the serializer, **with the
view the caller actually uses**. Grep the mobile client for which view it
requests if you are unsure — the client is the authority on what it receives,
not the model.

### Report the layer, not the word "tested"

"Request spec green" and "I clicked it" are different claims and both are
honest. **"Tested" on its own is not**, and neither is "verified on iOS" when
there is no Mac on this machine. "Verified on Android, reasoned for iOS" is the
honest sentence.

---

## E2E and QA — planned, deliberately not yet

When `karwan-mobile` exists, adopt `hatiwal-mobile/qa/` wholesale rather
than reinventing it: `qa.sh` as the single entry point, `features.yaml` as the
manifest, `FLOW_REGISTER.md` as the board, `UI_FINDINGS.md` for visual defects.
It is built to be portable — copy `qa.config.example.sh` to `qa.config.sh` and
the machinery needs no edits.

Read `hatiwal-mobile/qa/QA_HANDBOOK.md` **before writing the first flow.** It is
~3100 lines of already-paid-for lessons. The ones that will cost you first:

- **`assertVisible` never scrolls**, and `tapOn` never scrolls to its target.
  `scrollUntilVisible` with `centerElement: true` — without centring, an element
  can be "visible" at the very bottom edge, under the nav bar, where the tap is
  swallowed and the flow fails several steps later on a consequence.
- **A tap that lands on the keyboard is reported COMPLETED.** A bottom CTA under
  a text input is probably behind the IME.
- **Never ask `when: visible` about a screen you have not waited for** — it is a
  short poll that commits to a verdict, so the guarded block is skipped silently
  and the failure surfaces later naming something unrelated. This produced more
  fake app bugs than anything else in that rig.
- **Never take an expected string from a locale file.** 15% of Hatiwal's
  translation keys are dead; asserting one can never match. Take the string from
  the component, or the device, or better: assert a `testID`.
- **Matching is an anchored regex over the node's whole text**, so a label built
  from two translations needs a leading `.*`.
- **Read the bounds, not just the node names.** A five-pixel-tall input explains
  what no amount of waiting will.
- **A shared login helper can leave a flow signed in as the wrong user**, which
  presents as missing buttons.
- **`SILENT` is never a pass**: a flow whose assertions passed while logcat
  showed an API error is a defect. That is the bug users report as "nothing
  happened".
- Screen state carries **between** flows — the app is not restarted.

A last number worth remembering from that handbook: it opened at **4 of 214
flows passing**, and the note beside it says do not "improve" that number by
weakening assertions, because a false pass costs more than a red flow.

---

## Make the sources disagree — the rule five failures earned

This extends **"Prove the suite can fail"**. That rule asks whether a check *can* go red. This
one asks something narrower and harder: **when it stays green under a plant, is the code right
or is the test blind?**

Five times now a plant has changed real behaviour and the suite has not noticed. Three of them
share one cause: **the right answer and a plausible wrong answer looked identical in the
fixture**, so the test could not tell which one the code had used.

> ### 1. Make the sources disagree.
> For every value a test asserts, ask **where else the code could have got the same answer** —
> and build the fixture so those places differ.
>
> ### 2. Then ask who reads it.
> A test that a value is **stored** correctly is not a test that anything **uses** it.
> For a snapshot: freeze the copy, **mutate the source**, and assert the **consumer's
> behaviour** — never the column.

### The five, and which half each one needed

| What slipped | Why the fixture hid it |
|---|---|
| **Dispatch race** — 15 of 16 examples stayed green with the in-transaction re-check deleted | the offer-time and accept-time checks agree *unless the state changes between them*, so the fixture has to change it |
| **i18n boot loop** — the harness modelled one RTL scope, the device has two | `nativeRtl` and `committedRtl` agreed, so nothing could tell which scope the code read |
| **Size-class snapshot** — eligibility rewritten to read the LIVE catalog, 22 examples green | the live size and the frozen size agreed in every fixture |
| **`current_role`** — a guard-shaped method with no callers; a test asserting it ignored client input stayed green after it was rewritten to trust `params[:role]` | reachability, not fixtures: the code under test was dead |
| **Factory traits** — a courier holding no `customer` role, a user the rules forbid | reachability, not fixtures: the data could not occur through the app |

So: the first two rows above need **rule 1**, the third needs **rule 2**, and the last two need
the reachability questions — *does anything call this?* and *could this database state occur
through the app?*

### It was already right once, about money

`karwan-mobile`'s Cart test prices a basket at **905**, with the comment: *"400 × 2 is 800 and
the server also says 800 — so a passing test proves nothing unless the server's number is
DIFFERENT from what the device would compute."*

That instinct was applied to money and nowhere else. **Rule 1 is that instinct, generalised.**

### Where this bites next: everything about pricing is a snapshot

The per-vehicle rate work is snapshots end to end — `courier_fee` frozen at assignment,
`orders.courier_vehicle_type`, `trips.vehicle_type` frozen at quote. **The weak version of each
of those tests is the one that asserts the column kept its value, and it is the version a
careful person writes confidently.**

Each one needs: place or assign, **then mutate the live rate row**, then assert the **payout
calculation** still uses the frozen copy. If the rate table and the frozen amount agree in the
fixture, the test proves nothing about which one the code read.

Same for anything else that freezes: order line prices, the distance source on a quote, the
required size class, the merchant commission.

---

## A gate must tell code from prose — in both directions

Two failures, mirror images of each other, and the pair teaches more than either alone.

**One:** a rule's escape hatch was documented *inside* the escape hatch — so the documentation
itself satisfied the exemption and **turned the rule off** for everything after it.

**Two:** the separability gate failed on `ThemeProvider.tsx` and `useColors.ts` because **their
comments explain the rule by quoting the thing it forbids** — `role === "courier"`. The code was
correct; the prose describing why it is correct broke the check.

The second is the more dangerous one, because of what it teaches whoever hits it:

> **A gate that fails on its own documentation trains people to delete the documentation.**

Nobody deletes a comment maliciously. They delete it because the build is red, the comment is
"just a comment", and the deadline is real. Then the next person has the rule with no
explanation, and changes it.

**So: strip comments before matching, and assert on code.** A grep-based gate is a tiny parser,
and a parser that cannot tell a string from a statement will eventually be wrong in the
direction that costs most.

### And exempt by exact name, never by pattern

`app/index.tsx` and `app/_layout.tsx` legitimately know every role — routing by role IS the
entry point's job, and correction 18's own test is *"changing only the entry point"*. Those two
files are exempt **by exact filename**.

Not by a pattern. **An exemption wide enough to catch a third file hides the next violation** —
and it hides it in the one place the rule was written to protect.
