# karwan-api

JSON API for **Karwan** (کاروان) — a delivery and rides platform for Afghanistan,
starting with one neighbourhood in Kabul.

A *karwan* is a company travelling together carrying **goods and people**. That
is a description of the platform rather than a metaphor for it, which is why the
name survives the move from food-only to food-plus-rides.

**Latin spelling is always `Karwan`** — never Karvan, Kaarwan or Caravan.
Persian و transliterates as both v and w and people will search all of them, so
one spelling is picked and never varied. Identical in Pashto and Dari, all
shared letters, one wordmark for both locales.

This repo is the backend only. There is no web frontend here.

- Product brief: `CLAUDE.md`
- Screens and build phases: `docs/PRODUCT.md`
- Afghan usability constraints, which outrank generic mobile practice: `docs/AFGHAN_UX.md`
- Four-role architecture: `docs/ARCHITECTURE.md`
- Decision rights and definition of done: `docs/HOW_WE_WORK.md`
- Requirements as stated by the owner: `docs/REQUIREMENTS.md`
- Problems, traps and lessons: `docs/NOTES.md`
- Testing contract: `docs/TESTING.md`

## What this is, structurally

**One platform, two demand types, one courier pool.** In the style of Snapp
(Iran) or Meituan — several services sharing one account, one wallet and one
fulfilment network rather than several apps.

| | |
|---|---|
| `orders` | goods from a **merchant** — restaurant, store, pharmacy, bookshop |
| `trips` | a **passenger** from one pin to another |

They are separate tables on purpose. An order has line items, options, a
merchant and a prep time; a trip has two pins and no items. Forcing one table to
serve both would mean a dozen always-null columns and a status enum half of
whose values are meaningless.

What they genuinely share is shared **polymorphically**, not by merging:

- `offers` — a dispatch offer with a deadline, on either kind of job
- `status_transitions` — who moved this job, from what, to what, when, why
- `wallet_entries` — commission is owed on either
- `Dispatchable` — the concern holding the state machine, timeouts and scopes

Each job class supplies its own `STATUSES` / `TRANSITIONS` / `TERMINAL` /
`TIMEOUTS`, so a trip can have `arrived` and an order `preparing` without either
pretending to understand the other. **Nothing assumes exactly two demand types**
— a third (a person-to-person parcel) is a class and some rows, not a
restructure.

**One courier pool.** There is deliberately no `drivers` table. The person who
fulfils a job is one human with one wallet, one credit line and one commission,
whether the job is a meal or a passenger. The UI says "rider" in the delivery
tab and "driver" in the rides tab; the schema says `courier` and stays true for
both. This is also the economic point: food demand is spiky — lunch and dinner
— and a second demand stream on the same pool fills the idle hours. Utilisation
is the number that decides whether the unit economics work.

**Merchant kinds are a table, not an enum.** The supply side has been broadened
repeatedly; a new kind must be a row, not a migration. Food-specific fields
(`prep_time_minutes`) are nullable, because a book has no preparation time.

## Stack

| | |
|---|---|
| Ruby | 3.4.8 (`.ruby-version`) |
| Rails | 8.1, `--api` |
| Database | PostgreSQL 16, with `pg_trgm` |
| Auth | phone + OTP; bcrypt-digested codes, HMAC-digested session tokens |
| Authorization | Pundit |
| Serialization | Blueprinter (`ApplicationSerializer` + per-role views) |
| Pagination | Pagy 8.x via `paginate_blue` |
| Jobs / cache / cable | solid_queue / solid_cache / solid_cable — all Postgres |
| Files | Active Storage (photos, ID documents, address voice notes) |
| Tests | RSpec + FactoryBot + rswag |
| Deploy | Kamal |

Patterns are taken deliberately from `hatiwal-api` and `edu-safi` so tooling and
habits transfer. Two departures, both intentional:

1. **No `devise_token_auth`.** Phone number is the identity and OTP is the login
   — everyone has a phone, few have email. `devise_token_auth` is built around
   an email uid and would mean synthesising a fake email per customer.
2. **No Redis.** The three solid adapters run on Postgres.

## Local setup

```bash
docker compose up -d          # Postgres on 5417
bundle install
bin/rails db:prepare
bin/rails s -p 3017           # http://localhost:3017
```

The app runs on the host, not in a container — this box hosts several projects
and containers are the scarce resource. Only Postgres is containerised.

| Port | What |
|---|---|
| `3017` | this API |
| `5417` | its Postgres |

> **After editing an existing migration, delete `db/schema.rb` before
> re-migrating.** `db:migrate` against an empty database loads `schema.rb` and
> marks every migration as applied, so it will rebuild from the stale file and
> report success. See `docs/NOTES.md`.

## Money

**AFN only in v0, and every amount carries its currency explicitly.** Never sum
across currencies — group by it. Totals are computed and sent by the API, never
assembled on the client from whatever page happened to load.

Model A, per food order: the courier advances `food_total − commission` to the
merchant at pickup, collects `customer_total` from the customer, keeps their
fee, and is left holding our commission — which is our entire exposure per job.
On a trip it is simpler: the courier collects the fare, keeps it, and owes
commission from their prepaid wallet. **No advance to anybody on a ride.**

`payment_status` tracks that money as an explicit column — `pending → collected
→ settled` — never derived. It is named for payment rather than cash so a
digital provider later reuses it instead of adding a second mechanism.

The courier wallet is **prepaid, never a debt**: deposit credit, each job
deducts commission, and at the floor the app stops assigning work. Balances and
ledger amounts are **signed and bidirectional**, because online payment inverts
the relationship — we would hold the money and owe the courier their fee.

## Before every commit

```bash
bundle exec rspec       # zero failures
bundle exec rubocop     # zero offenses
bin/rails zeitwerk:check
```

Plus the seven-question self-review in `docs/HOW_WE_WORK.md`. The first one
matters most: **can this check fail?** Prove it by planting the bug it should
catch.
