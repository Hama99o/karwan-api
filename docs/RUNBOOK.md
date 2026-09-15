# Runbook — bringing Karwan up, in order

Run `bin/preflight` first. It checks steps 1–5 below and names the command that
fixes whatever is missing. **Everything here is derived from a failure that
actually happened**, which is why the order is not advice.

```
bin/preflight          # is the stack ready, and is it OURS?
```

## Why the ORDER is the point

The first device run of this app produced twelve findings and **two of them were
nothing to do with the app**:

- **F-06** — nothing was serving the API at all, so every authenticated screen
  had no data path and the run could not test what it came to test.
- **F-13** — the rig's own health check was pointed at another application (port
  3000), and then at an endpoint this API does not have (`/categories`, which is
  Hatiwal's). It could only ever answer wrongly.

Each step below therefore states **what it proves**, because every one of those
failures was a step that looked satisfied and was not.

---

## 1 · Postgres — `docker compose up -d`

The app runs on the host; only Postgres is containerised (one fewer container on
a box that runs five sessions). Port **5417**, offset from every other project
here: 5432 booklet · 5443 multi_magic · 5456 studio · 5407 hatiwal · **5417 us**.

*Proves:* something accepts connections on 5417. Not that our database exists.

## 2 · Schema — `bin/rails db:prepare`

`db:prepare` rather than `db:migrate`, because production has **four**
databases — primary, cache, queue, cable — and only the first is created for
you. A missing queue database means jobs silently have nowhere to run.

*Proves:* no pending migrations. Asked of Rails, never of `psql`: the
credentials live in `database.yml` and a second copy is how the two drift.

## 3 · Reference and sample data — `bin/rails db:seed`

**This is not optional for a device run.** There is no fake data anywhere in the
app (CLAUDE.md correction 17), so against an empty database every screen
correctly shows its empty state and a run proves nothing about layout, RTL or
spacing. Sample data is skipped in production only.

*Proves:* merchants are browsable, categories exist.

## 4 · The API — `bin/rails s`

**No `-p`.** 3017 is the default now (`config/puma.rb`, `DEFAULT_PORT`). It used
to be Rails' own 3000, which on this box is a **different live application** — so
the API only landed on the right port when whoever started it remembered the
flag, and when they did not, a health check passed against a stranger.

*Proves:* `/up` returns 200 — **and nothing more than that.**

## 5 · …and that it is KARWAN — the step everyone skips

**A STATUS CODE IS NOT AN IDENTITY.** Measured, today: the unrelated app on port
3000 answers `/up` with a **200**, because it is also a Rails app and Rails ships
that route. A health check that stops at step 4 is worthless on a shared box.

So `bin/preflight` asserts the *payload* of
`/api/v1/public/merchant_categories` is ours. Pointed at 3000 it correctly
refuses — proven by running `PORT=3000 bin/preflight`, which is the standing way
to check this check still works.

Public, unauthenticated, cheap, and it answers "which application is this?"
rather than "is something alive?". The rig uses the same endpoint via
`API_PROBE_PATH` in `qa/lib/common.sh`.

---

## 6–8 · The device half — the rig's, not this repo's

```
cd ../karwan-mobile
qa/qa.sh doctor        # re-checks the above from the rig's side, plus the device
qa/qa.sh up            # ONE emulator. Measured safe: two. Measured FATAL: three.
qa/qa.sh flows
```

Three things that are not obvious and cost a run each:

- **Metro is :3028 and the API is :3017.** Two different services; they never
  needed to agree. Metro is the JS bundler, and `adb reverse` does not get the
  dev client connected — it fetches from `10.0.2.2:3028`, the emulator's alias
  for this host (F-08).
- **The first bundle of a session is ~5 minutes cold** (3454 modules) and the dev
  client gives up first, so the first flow used to fail for no app reason.
  `metro_prewarm()` now makes one host-side request before the first feature
  (F-09).
- **Record the commit you tested.** The first run was partly invalidated because
  the tree moved under it — `c4eeb0c` landed mid-run and changed six screens
  from demo data to the real API (F-12).

## What "ready" does not mean

`bin/preflight` green means the backend is serving real data. It says nothing
about the app rendering, the map painting, RTL layout, or 360dp — those are four
different claims and only a device answers them. `qa/QA_HANDBOOK.md` is explicit
about that distinction and it is the reason the first boot found what it did.
