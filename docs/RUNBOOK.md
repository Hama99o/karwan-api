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

## Routing: running OSRM

Hamma9900 has decided to price on roads. Two separate facts, and keeping them
separate is what makes the flip reversible in a minute:

1. **A router is reachable** — `OSRM_BASE_URL`, an env var.
2. **We price on roads** — the `routing_distance_source` setting, editable in
   the console. Until it says `osrm`, the resolver takes the straight line and
   **records that it did**, on every order.

So turning it on in production is: start the accessory, then type one word in
the Config screen. Turning it off is typing the other word — no deploy, and
orders already placed keep the amounts they were quoted.

### Locally

The `deploy.yml` default is `http://karwan_api-osrm:5000`, a container name
that resolves only inside the shared Docker network. **Rails runs on the host
here, so it cannot resolve that** — publish the port and override the URL:

```bash
docker run -d --name karwan_osrm -p 127.0.0.1:5000:5000 \
  -v $HOME/Apps/Personal/Karwan/karwan-map/tmp/osrm:/data:ro \
  ghcr.io/project-osrm/osrm-backend:latest \
  osrm-routed --algorithm ch --mmap=1 /data/afghanistan.osrm

OSRM_BASE_URL=http://localhost:5000 bin/rails s      # or runner, or console
```

`--mmap=1` is not optional on this box: **32 MB resident with it, ~400 MB
without**, and the 400 MB is unreclaimable. `docker stop karwan_osrm` when done.

### The data is not in the image

The ~512 MB `.osrm.*` serving set lives at `karwan-map/tmp/osrm/` and must be
copied to `/var/karwan/osrm` on the production host before the accessory
starts. `osrm-extract` is the expensive step — 2.29 GB peak — and it does not
belong on a production box; build it where the map service is built.

### What it actually costs, measured rather than estimated

Four Kabul pairs, same pins, both sources:

| Pair | straight | road | ratio | fee change |
|---|---|---|---|---|
| Shar-e-Naw → airport | 4.46 km | 5.53 km | 1.24× | +15.3% |
| Shar-e-Naw → Karte Naw | 3.61 km | 4.60 km | 1.28× | +16.3% |
| Kote Sangi → Macroryan | 8.89 km | 11.20 km | 1.26× | +20.2% |
| a 600 m hop | 0.58 km | 0.85 km | 1.47× | **0%** |

**The fee moves less than the distance**, and the often-quoted ~29% was a
distance ratio rather than a fee change: the fixed base dilutes it, and on a
short hop the minimum fee absorbs it entirely. That is the number Hamma9900
should be making his pricing decision against.

### And on a LIST, measured over 20 seeded merchants from Shar-e-Naw

Four hand-picked pairs understated it. Across a real page the road/straight
ratio runs **1.20× to 2.35×**, and the worst case matters more than the
average: one merchant 4.91 km away in a straight line is **10.30 km by road**.
Priced on crow flight, that customer was quoted less than half the distance
the courier rides — which is the "unfair" Hamma9900 named, from the courier's
side as well as ours.

**THE ORDER OF THE LIST CHANGES.** "Nearest first" is not the same list by the
two methods: over those 20, the pharmacy drops from 8th to 12th and
کباب شهر نو rises from 10th to 7th. So this is a product change and not only
a pricing one — the first screen a customer sees is now ordered by how far
they would actually travel. He should see that rather than discover it.

**The duration is still ours.** OSRM returned 7.7 minutes for the 5.53 km pair
— 43 km/h, because `car.lua` is free-flow and Afghan maxspeed tags are sparse —
and we quote 19 minutes from `eta_average_speed_kmh`. That survives the switch
and is asserted by a spec.

## What "ready" does not mean

`bin/preflight` green means the backend is serving real data. It says nothing
about the app rendering, the map painting, RTL layout, or 360dp — those are four
different claims and only a device answers them. `qa/QA_HANDBOOK.md` is explicit
about that distinction and it is the reason the first boot found what it did.
