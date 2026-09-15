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

### Report the layer, not the word "tested"

"Request spec green" and "I clicked it" are different claims and both are
honest. **"Tested" on its own is not**, and neither is "verified on iOS" when
there is no Mac on this machine. "Verified on Android, reasoned for iOS" is the
honest sentence.

---

## E2E and QA — planned, deliberately not yet

When `dastarkhwan-mobile` exists, adopt `hatiwal-mobile/qa/` wholesale rather
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
