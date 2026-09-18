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

---

## Deploying — `kamal seed` is a STEP, not an alias somebody may type

`config/deploy.yml` defines `migrate` and `seed` under **`aliases:`**. Aliases are
shortcuts a person types; they are not hooks, and there is no `.kamal/hooks/`
directory.

**Migrations are not the problem: `bin/docker-entrypoint` runs `db:prepare`
whenever the container starts the server**, byte-identical to `hatiwal-api`'s.
So the schema is current after every deploy and `kamal migrate` is
belt-and-braces you can run if you want to watch it.

**`kamal seed` matters from the SECOND deploy onward.** A first deploy seeds
itself — `db:prepare` creates the database, loads the schema and runs the seeds,
verified by booting the production image against an empty database and counting
48 `settings` rows. But once the database exists it only migrates, so **a
setting added in a later release never appears on the running server**:
`Setting.fetch` serves its code default and the console has no row to type in.
`hatiwal-api` behaves identically. Safe to run every time — the reference half
is idempotent and never overwrites a tuned value.

**A first deploy, in order:**

```
kamal deploy
kamal migrate        # bin/rails db:prepare — creates cache/queue/cable too
kamal seed           # bin/rails db:seed — reference data only in production
```

### A FOURTH STEP, but only after a search change — and it is also silent

`search_text` is a STORED column, built when a record is saved. So a change to
the romanisation table, the fold table or `TermDictionary` **does not reach a
single existing row**: new merchants get the new spelling coverage and every
merchant already in the database keeps whatever the old code produced. Nothing
errors, nothing logs, and the only symptom is a merchant nobody can find.

After deploying any change under `app/services/search/`:

```
kamal app exec 'bin/rails runner "Merchant.rebuild_search_text!; CatalogItem.rebuild_search_text!"'
```

Idempotent, and it rewrites `search_text` only. **Required for the 2026-09-18
variant-letter fix**: every merchant whose name carries `ګ`, `ى`, `ئ` or `ة` was
indexed with that letter silently deleted, and rebuilding is the only thing
that repairs those rows.

**Step 3 is the one that gets forgotten, and forgetting it is silent.**
`Setting.fetch` falls back to each definition's default when no row exists, so
the app boots, prices orders and delivers food perfectly — on values **nobody
can see or change**. The console lists `settings` ROWS, not definitions, so the
Config screen is simply short. Correction 13's whole premise, that Hamma9900
retunes prices weekly from the console with no deploy, quietly stops being true
and nothing reports an error.

**`bin/preflight` now catches it** — it lists the missing keys by name, warns
locally and **fails on a deployed box**. Run it against the deployed
environment after `kamal seed`, not only locally.

**`kamal seed` is safe on EVERY deploy**, not just the first: `db/seeds.rb`'s
reference half is idempotent, refuses sample data in production, and
`Setting.seed_defaults!` only writes a value when the row has none — so a
number Hamma9900 has tuned is never overwritten.

---

## Every ENV key the app reads, and where it comes from

**37 keys, classified from the source rather than from memory** (2026-09-17).
This is the table to read at 2am with a broken deploy. It is enforced by
`spec/config/deploy_env_spec.rb`, which scans for `ENV.fetch`/`ENV[...]` — so
key 38 has to appear here or the gate goes red.

### Declared in `deploy.yml` → `env: clear:` — non-secret, visible in the repo

`APP_BASE_URL` · `DATABASE_HOST` · `DATABASE_PORT` · `DATABASE_USERNAME` ·
`RAILS_LOG_TO_STDOUT` · `SOLID_QUEUE_IN_PUMA` · `OSRM_BASE_URL`

### Declared as SECRETS — named in `deploy.yml`, resolved by `.kamal/secrets`

`RAILS_MASTER_KEY` · `DATABASE_PASSWORD` (and `POSTGRES_PASSWORD`, read from
the same line so app and accessory cannot disagree) · `KAMAL_REGISTRY_PASSWORD`
· `FCM_PROJECT_ID` · `FCM_ACCESS_TOKEN` · **`SMTP_ADDRESS`** ·
**`SMTP_USER_NAME`** · **`SMTP_PASSWORD`** · **`SMS_PROVIDER`**

> **The four in bold are declared and EMPTY on purpose.** They are the two
> gateways correction 14 permits — SMS for one-time codes, SMTP for the
> password-reset code — and both are Hamma9900's decision and his money. A
> named slot with no value plus `bin/preflight` refusing a deployed box without
> `SMTP_ADDRESS` is the honest shape. **A plausible placeholder would be
> worse than a blank**: it boots, it reads as configured, and the failure lands
> somewhere nobody predicted.
>
> Until `.env.production` carries them, `kamal secrets` resolves them to empty
> and the deploy is refused by preflight rather than starting misconfigured.

### Safe documented defaults in code — nothing to declare

`ADMIN_MAILER_SENDER` and `MAILER_FROM` (`no-reply@karwan.af`) · `APP_DOMAIN`
(`api.karwan.af`) · `SMTP_DOMAIN` (`karwan.af`) · `SMTP_PORT` (`587`) · `PORT`
(`3017`, and `config/puma.rb` is where that lives — see the port entry above) ·
`RAILS_LOG_LEVEL` · `RAILS_MAX_THREADS` · `DATABASE_URL` (development only;
`config/database.yml` derives the test URL from it) · `KARWAN_SEED_SAMPLE`,
`KARWAN_SEED_SCALE`, `KARWAN_SEED_STRESS`, `KARWAN_SEED_RESET_STRESS`

### Supplied at deploy time, deliberately absent from the file

`KAMAL_HOST` · `KAMAL_PROXY_HOST` · `KAMAL_IMAGE` · `KAMAL_REGISTRY_USERNAME` ·
`SSH_USER` · `SSH_KEY_PATH`

**`KAMAL_HOST` having no default IS the "complete without an IP" design.**
`kamal config` refuses without it rather than inventing a server, which is
correct — and it is why validating this file locally needs
`KAMAL_HOST=… KAMAL_PROXY_HOST=… bundle exec kamal config`, not a bare run.

### Set by the runtime, not by us

`BUNDLE_GEMFILE` (Bundler) · `CI` (the workflow) · `PIDFILE` and
`WEB_CONCURRENCY` (Puma). A nil is the documented "not set" for each.

### What was wrong before this table existed

The app read five `SMTP_*` keys and `SMS_PROVIDER` and **`deploy.yml` had
nowhere to put any of them** — so `bin/preflight` demanded a value the deploy
could not supply, and the two halves of the same requirement did not meet.
Found by counting what the app reads against what the deploy declares, which is
the check the spec now performs on every run.

---

# THE FIRST DEPLOY — the ordered list, for a night with nobody to ask

**Shape copied from `../../Hatiwal/DEPLOYMENT.md`** (read 2026-09-17), which is
backed by a real deployment with real users. Karwan differs in three places and
each is marked **DIFFERENT FROM HATIWAL** rather than silently diverging:
OSRM as a fourth accessory, `kamal seed` as a required step, and `bin/preflight`
as the gate that says whether it worked.

Do these in order. Every step says what it proves, because a step that looks
satisfied and is not is what this whole file exists to prevent.

## 0 · Before you start — two decisions that are yours, not the machine's

**Nothing below works without these, and no code can supply them.**

- **The SMS gateway.** Chosen on price per message to Afghan networks. Without
  it nobody in Kabul can receive a sign-in code, so **no real person can use the
  app at all.** The adapter is `Notifications::SmsClient` and swapping the
  provider is an afternoon.
- **The mail host.** Carries the password-reset code for anyone who signs in
  with an email. **Fill `SMTP_ADDRESS` before step 6 or `bin/preflight` will
  refuse to pass**, by design.

Both have named, empty slots in `deploy.yml` and `.kamal/secrets`. Empty is
deliberate — a placeholder that looks real would boot and fail somewhere you
would not think to look.

## 1 · Provision the VPS

Ubuntu LTS, Docker installed, an SSH key you hold, and a user Kamal can use.
Hatiwal runs on an OVH box as `kamal@<ip>`; Karwan is a **fourth service on the
same box**, so if Hatiwal is already there this step is done.

*Proves:* you can `ssh` in without a password prompt.

## 2 · DNS, or a nip.io name if you have no domain yet

Point a hostname at the IP. Hatiwal uses
`api.hatiwal.<ip>.nip.io` for exactly this reason — **you do not need to buy a
domain to deploy.** `kamal-proxy` gets the certificate from Let's Encrypt.

*Proves:* the name resolves to your IP. `dig +short <host>`.

## 3 · The isolated Docker network

```bash
ssh kamal@<ip> "docker network create karwan_api-net"
```

*Proves:* the app, Postgres and OSRM can reach each other and nothing else can.
**Karwan's Postgres is on 5435 and bound to 127.0.0.1**, so it is not reachable
from the internet at all.

## 4 · `.env.production` — where every value comes from

```bash
cp .env.production.example .env.production   # then fill it in; it is gitignored
```

| Variable | Where the value comes from |
|---|---|
| `DATABASE_PASSWORD` | `openssl rand -hex 32` — invent it here, nothing else knows it |
| `KAMAL_REGISTRY_PASSWORD` | a Docker Hub access token |
| `RAILS_MASTER_KEY` | **not here** — `.kamal/secrets` reads `config/master.key` |
| `SMTP_ADDRESS` `SMTP_USER_NAME` `SMTP_PASSWORD` | **your mail provider, from step 0** |
| `SMS_PROVIDER` | **your SMS gateway, from step 0** |
| `FCM_PROJECT_ID` `FCM_ACCESS_TOKEN` | Firebase console. Absent, push stays quiet rather than raising — a missing push must never fail an order |

`.gitignore` covers `/.env*` and `/config/*.key`, both verified. **Never put a
literal into `.kamal/secrets`** — it is committed; a spec fails the build if
anybody does.

*Proves:* nothing. Filling a file proves nothing until step 6.

## 5 · `kamal setup` — first deploy, and it does a lot

```bash
KAMAL_HOST=<ip> KAMAL_PROXY_HOST=<hostname> kamal setup
```

Bootstraps the server, boots the accessories, builds and pushes the image, and
starts the app. **DIFFERENT FROM HATIWAL:** Karwan has a third accessory,
**OSRM**, which needs the Afghanistan extract at `/var/karwan/osrm` on the host
before it will start. Build it the way `karwan-map` builds its tileset — from
the same `afghanistan-latest.osm.pbf`, or you will route over roads the map
does not draw.

**Migrations need no step.** `bin/docker-entrypoint` runs `db:prepare` whenever
the container starts the server, which also creates the cache, queue and cable
databases. `kamal migrate` exists as an alias if you want to watch it happen.

*Proves:* containers are up. `kamal app details`.

## 6 · `kamal seed` — REQUIRED, and forgetting it is silent

```bash
kamal seed        # bin/rails db:seed — reference data only in production
```

**DIFFERENT FROM HATIWAL in emphasis, not mechanism:** both projects seed by
hand, and in Karwan the consequence is sharper. `Setting.fetch` falls back to
each definition's default when no row exists, so **the app boots, prices orders
and delivers food perfectly on values you cannot see or change.** The Config
screen is simply short. Correction 13's whole premise — that you retune prices
weekly from the console with no deploy — quietly stops being true, and nothing
reports an error.

Safe on every deploy, not just the first: the reference half is idempotent,
refuses sample data in production, and never overwrites a number you have tuned.

*Proves:* the Config screen has every setting in it. **On a first deploy this
step is belt-and-braces** — `db:prepare` already seeded when it created the
database. It becomes load-bearing on every deploy after that, because a setting
added in a later release materialises no other way.

## 7 · `bin/preflight` — the gate that says whether any of this worked

**DIFFERENT FROM HATIWAL: Karwan has one and Hatiwal does not.** Run it
against the deployed environment, not only locally:

```bash
kamal app exec -i "bin/preflight"
```

It fails — not warns — on a deployed box for: a pending migration, a missing
`SMTP_ADDRESS`, or a `Setting` with no row. Each names what is missing and the
command that fixes it.

*Proves:* the stack is ready **and it is ours** — it asserts the API's identity
rather than that something answered a 200.

## 8 · The three curls that prove it is serving

```bash
curl -sS https://<host>/up                               # → 200
curl -sS https://<host>/api/v1/public/merchants | head   # → JSON, not an error page
curl -sS https://<host>/api/v1/public/app_config | head  # → the support number
open https://<host>/admin                                # → the ops console login
```

**The second one is the real test.** `/up` is answered by any Rails app —
including the unrelated one on port 3000 of this box, which is how a health
check once reported a green API that was a stranger's.

## 9 · If it is wrong — the rollback sentence

```bash
kamal rollback              # previous image, immediately
kamal app logs -f           # what actually happened
```

**The first deploy is the one most likely to need this**, and a rollback is
cheap: the image is already on the server. The database is the part a rollback
does **not** undo — migrations are forward-only here, so a bad migration is
restored from a dump, not rolled back. Take one before any deploy that migrates
anything you care about:

```bash
kamal accessory exec db "pg_dump -U karwan karwan_production" > karwan-$(date +%F).sql
```
