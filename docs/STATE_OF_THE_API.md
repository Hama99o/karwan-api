# The state of karwan-api — handoff, 24 Sept 2026 (late)

For whoever picks this up cold. **It's a state, not a changelog:** what is
true of the API tonight, how sure we are of each thing, and what is waiting on
whom. Commit hashes point at the evidence. Deeper records:
`docs/NOTES.md` (findings and lessons), `docs/RUNBOOK.md` §9.1 (backups),
`docs/API_VOCABULARY.md` §B, §E, §E2 and §F (wire contracts).

**The whole suite, four times, on four seeds** (the latest: `92d5e2d`, seed 13225, EXIT 0, 3,162 examples, 0 failures, 3 pending; before it `93e4f66`, seed 32509, 3,127 examples):
- `4864764`, seed 47846: 204 files, 3,061 examples, 0 failures, 3 pending.
- `e1bbdae`, seed 41528: **209 files, 3,082 examples, 0 failures, 3
  pending**, exit 0, no errors outside examples, 14m47s, memory stall zero
  throughout.

The 3 pending are deliberate: the owner's two open money decisions, and one
empty design spec. After any commit since `e1bbdae`, run it again before
trusting a single targeted green (NOTES has the dated example of a targeted run
missing a break).

**When to start a whole run** (restated 25 Sept by Hamma9901; supersedes "load
under 8"): **start when memory pressure is at zero and available RAM is
comfortable, with the stall guard armed. Load is context, not a gate.** The
guard reads `full avg10` from `/proc/pressure/memory` every 10 s and stops the
run's process tree, by its recorded PID, above 0.5. Use
`TEST_DB_SUFFIX=<yours>` so no one else's test database is touched. Nothing is pushed: `main` is **152 commits ahead of `origin/main`** at the time of writing, and pushing is the owner's call.

---

## 0 · Which documents you can trust as STATUS

There are two kinds of document here, and only one of them goes stale.
- **Briefs state intent**, and are read with `CLAUDE.md`'s numbered
  corrections: `CLAUDE.md`, `PRODUCT.md`, `ARCHITECTURE.md`, `DESIGN.md`,
  `MOBILE.md`, `AFGHAN_UX.md`, `IDENTITY_AND_ROLES.md`. They're old (15–16
  Sept) and that's fine: they say what the product is for, not what the code
  does today.
- **Status documents claim what is true now**, and these are the ones to
  check:
  - `NOTES.md` (its open list was re-read against the code on 24 Sept, and
    stale entries marked in place);
  - `RUNBOOK.md`, `API_VOCABULARY.md`, and this file;
  - **`MAP_AND_ROUTING.md` (19 Sept) held one stale status claim**, that
    pricing used straight-line distance. It's annotated in place.
- **Documents that cannot go stale unnoticed**, because a spec fails when they
  do: `API_SURFACE.txt` (`api_surface_spec`), and `API_VOCABULARY.md`'s
  counts and values (`api_vocabulary_spec`, `push_keys_are_published_spec`).

If a status claim here disagrees with the code, the code wins. Fix the line
and say so.

## 1 · Finished, and what "finished" means

"Finished" here means all of these hold:
- the defect was reproduced first, or the gap measured;
- the fix has a spec at the layer that ships;
- the spec goes RED when the fix is removed (a "plant"), and was restored
  byte-identical;
- the neighbouring specs were run.

A fix without a plant isn't on this list.

### Concurrency: two taps, two requests, two sweeps at once
| what | where it's held |
|---|---|
| A courier's double "delivered" delivered twice → the step is decided under the job's row lock | `3c731d3`, `advance_job_service_race_spec` (threads) |
| A shop's double accept wrote two accepts and a 500 → `transition_to!` locks and compares the STORED status. Every caller shares it | `388c27e`, `two_moves_at_once_spec` |
| A decline and the expiry sweep made two live offers → one dispatch of a job at a time (row lock) | `95bf342`, `two_offers_at_once_spec` |
| A decline racing the sweep on the SAME offer: **safe**, because both write the offer row first. The lock is the second guard | `6dacc39`, `decline_while_the_sweep_expires_spec` |
| A retry of an already-done courier step gets 200 and the job, not a 422 | `b4cb94b` |

### Money
| what | where |
|---|---|
| A settle pressed twice wrote a phantom surplus → the wallet is locked and an empty settle refused | `03e2384` |
| Reimburse consults a policy | `9be935d` |
| A delivery pin outside Afghanistan was priced and PLACED (a (0,0) pin became a 162,396 AFN order) → refused as `outside_service_area` | `7a586e9` |
| An order places at no more than the customer was shown (`expected_amount_to_pay_in_cash`: higher → 409 with a new quote; lower → places lower, shown amount kept) | `0ebcb2b`, §E2 |
| An order places once per checkout (`Idempotency-Key`, compared by a request fingerprint, per customer) | `86630b9`, §E |
| A shop suspended or removed before the weekly statement still gets its week | `fc3918d` |
| The console's per-km fee says "by road", which is what it charges | `21bd9ac` |

### Positions, arrival, map
| what | where |
|---|---|
| A courier fix that can't be a place ("abc", (0,0), off the planet) is refused and doesn't refresh freshness | `faf6d27` |
| A delivery arrival records where the courier was, and when that fix was taken | `78a4278` |
| Every offer records the fix dispatch chose the courier by (for measuring staleness later) | `b26a3a4` |
| `located_seconds_ago` on tracking and offers, by the server's clock; null means never seen | `a891f99` |
| The offer says which distance is a straight line and which is by road | `e28cad0` |
| A console report of the real orders whose road ran over k× the straight line (measures, re-prices nothing) | `ae83796` |

### Console
| what | where |
|---|---|
| Delete discards anything discardable; Restore on catalog items and categories; each hard delete names the schema fact that makes it safe | `ab17091` |
| A double click can't double-submit; `data-confirm` prompts are actually asked (they never were) | `f5fdb5c`, browser test in `test/console_submit_guard/` |

### Push (server half; no handler or Firebase yet, both the owner's)
| what | where |
|---|---|
| Only the shop's new-order alert is an alarm; the rest are quiet | `f9e876b` |
| Deep links name the event and the record: `karwan://open/<event>/…` | `71981b5`, `4864764` |
| The new-order alert carries real words, in the owner's saved language, **mirrored from the app and gated text-for-text** | `71981b5`, `708588d`, `push_copy_mirrors_the_app_spec` (it SKIPS where karwan-mobile isn't checked out beside the API, so CI alone won't guard it) |
| A push carries identifiers, not content: no review note, no phone numbers. The allowlist is gated per notifier | `17626bc`, `a_push_carries_identifiers_not_content_spec` |
| A ride's arrival notice has its own words | `5593e94` |

### Performance
| what | where |
|---|---|
| Dispatch is FLAT in the number of couriers: the busy check and the cash check are pooled, settings are read once per request. **10 queries for 2 eligible couriers and 10 for 8** (was 17 and 41) | `cc7d3c4`, `fbf36a6`, `f49aa31` |
| The merchant board answers 304 before its 13 queries, keyed to the minute | `e93db6e` |

### Instruments: the specs that check the specs
24 gates examined. 17 were blind by construction (a hand list, one folder, one
column type, one line at a time). 2 of those were hiding real bugs (the console
hard-deleting menu items; two app-read enums unpinned), and 11 were widened.
NOTES has the full table, "WHAT EACH GATE CANNOT SEE". Also rebuilt: the
console policy sweep, now route-derived (`90d7bbf`).

---

## 2 · Measured, and only inferred

**Measured**, at the layer that ships:
- **production compresses** (Thruster: the board 2,829 → 563 bytes);
- **production speaks HTTP/2** (kamal-proxy, observed on Hatiwal's live
  stack);
- **every hot query has a usable index** (42 shapes, re-planned with
  seqscans off);
- **dump and restore work** against this schema, extensions included;
- road/straight ratio across 600 realistic Kabul pairs: median 1.60×, p99
  3.6×.

**Inferred, not proven:**
- that the 7 anonymous 778.6 MB Docker volumes are repeated test restores
  (from size alone);
- that the worst detour routes are OpenStreetMap data gaps rather than real
  barriers (from the route shape; no ground truth);
- one test order for each race spec, not every order.

**Re-measured after the pooling (25 Sept) and attributed:** a whole dispatch
decision over 95 couriers is about **100 ms** (harness p50 130 ms and p95 157 ms,
of which about 32 ms was the harness's own bulk update), with 16 queries and
27 ms in the database. The old 330–1,000 ms is not today's cost. NOTES has the
breakdown.

---

## 3 · Waiting on Hamma9900 (decisions, not work)
- **Console logins:** will anyone else hold one? It decides whether the 104
  console actions with no policy need 104 policies (`every_action_consults_a_policy_spec`
  holds the list honestly).
- **The detour cap**, and who pays if the fee is capped (a cap cuts the
  courier's pay unless the platform tops it up). Costed in NOTES: at k = 3,
  3.8% of orders and about 136 AFN per 100 orders.
- **A maximum delivery distance** from the shop. Only the country is
  enforced; a 171 km in-country order places.
- **The ride fare rule:** honour the SHOWN fare exactly, or refuse-if-higher
  like food?
- **Backups:** build `bin/backup` and `bin/restore-check` (RUNBOOK §9.1).
  About a day of work and a few euros a month. **Hatiwal's newest backup is
  from 1 Sept**, and Hatiwal is live.
- Standing ones: the SMS provider, the support phone, 8 untranslated strings,
  the courier credit line, the §2 commission channel, the premium uplift.
- On the box: removing the zombie 9 GB buildx volume (one command, refused
  to us); a read-only look inside the 10.5 GB anonymous Postgres volume.

## 4 · Things found on 25 Sept that the next session must know
- **The suite's exclusive-database lock could vanish mid-run.** It was held
  on ActiveRecord's pooled connection. When AR replaced that connection
  (seen after `shifts_spec.rb:135` in a long run; the cause is not
  established), the lock went too. From then on a second run could truncate
  the same database, and the failures would look like flakiness nobody can
  reproduce. **It now lives on its own raw PG connection** (`spec/rails_helper.rb`).
  A `reconnect!` probe is red on the old helper and green on the new one.
- **Production's cache is not solid_cache.** It's the default FileStore in the
  container. It **must move before a second web container exists**, or every
  throttle becomes per-container. `config/deploy.yml` and NOTES have the
  steps. Correction 3 in `CLAUDE.md` still says otherwise; that's for the
  user to change.
- **Throttles now count per identifier** on sign-in and password reset, with
  per-IP backstops (1,200, 300 and 600 for registration). Every 429 carries
  `retry_after_seconds`.
- Dispatch was re-measured under load 5–7 and attributed (§2): about 100 ms per
  decision over 95 couriers. Nothing to fix at launch scale.

## 5 · Waiting on karwan-mobile (the app halves of contracts already live here)
- Send `Idempotency-Key` from checkout-open, and `expected_amount_to_pay_in_cash`.
  Handle 409 `price_changed` and 409 `idempotency_key_reused`.
- `outside_service_area` on the checkout path.
- The board's `If-None-Match` (reported built).
- Show the offer's two distances as different kinds of number.
- The push handler; words for the ride keys; the `open/…` routes.

## 6 · What I would do next
1. **The whole suite** after any new commit. The last clean whole run was at `92d5e2d`: seed 13225, EXIT 0, 3,162 examples, 0 failures, 3 pending, run DETACHED (a tool background task is killed at about 14 min 22 s; NOTES has it). A pass is an exit code plus the expected count, never the summary line alone.
2. ~~The dispatch re-measure~~: done 25 Sept (§2). At about 1,000 couriers,
   filter by distance in SQL before instantiating the pool.
3. **The rest of the ride door**, when the owner says go: NOTES "THE RIDE DOOR —
   build it from this list". Its first step, the console override, is built.
4. **`bin/restore-check`**, when the owner says go. The two-part check
   (restored == source; balances == entries) is designed in RUNBOOK §9.1.

## 7 · How this work was checked (so the next session can hold the same line)
- **Reproduce before fixing.** Several suspicions tonight were WRONG, including
  a double commission and a stale-copy race, and a reproduction is what said
  so.
- **Plant the bug back.** Four specs written tonight first passed with their
  fix removed, and each was rebuilt until it could fail. A green spec that
  can't go red is the default, not the exception.
- **Measure at the layer production uses.** Two of the night's findings
  ("no compression", "no HTTP/2") were true of the dev server and false of
  production.
- **Enumerate the reachable side, not the declared side.** Routes, not
  policies; FKs, not a hand list of tables; every enum, not the typed ones.
- **Commit by named path; never `git add -A`, never `git stash`; don't push.**
