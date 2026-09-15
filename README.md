# dastarkhwan-api

JSON API for **Dastarkhwan** (دسترخوان) — a cash-on-delivery food-delivery app for
Afghanistan, starting with one neighbourhood in Kabul.

This repo is the backend only. It serves three roles from one account —
customer, restaurant, rider — plus an ops console for admin. There is no web
frontend here.

- Product brief: `../CLAUDE.md`
- Screen-level spec and build phases: `../docs/PRODUCT.md`
- Decision rights and definition of done: `../docs/HOW_WE_WORK.md`

## Stack

| | |
|---|---|
| Ruby | 3.4.8 (`.ruby-version`) |
| Rails | 8.1, `--api` |
| Database | PostgreSQL 16 |
| Auth | phone + OTP, bcrypt-digested codes and session tokens |
| Authorization | Pundit |
| Serialization | Blueprinter (`ApplicationSerializer` + views) |
| Pagination | Pagy 8.x via `paginate_blue` |
| Background jobs / cache / cable | solid_queue / solid_cache / solid_cable — all Postgres |
| Tests | RSpec + FactoryBot + rswag |
| Deploy | Kamal |

Patterns are taken deliberately from `hatiwal-api` and `edu-safi` so that tooling
and habits transfer. Two departures, both intentional:

1. **No `devise_token_auth`.** Phone number is the identity and OTP is the login
   — "everyone has a phone, few have email". `devise_token_auth` is built around
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

## Money

**AFN only in v0, and every amount carries its currency explicitly.** Never sum
across currencies — group by it. Totals are computed and sent by the API, never
assembled on the client from whatever page happened to load.

The cash model (Model A) is in `../CLAUDE.md`. The short version, per order:
the rider advances `food_total − commission` to the restaurant at pickup,
collects `customer_total` from the customer, keeps their fee, and is left
holding our commission. `orders.cash_status` tracks that money as an explicit
column — `pending → collected → settled` — never a derived value.

## Before every commit

```bash
bundle exec rspec       # zero failures
bundle exec rubocop     # zero offenses
```

Plus the seven-question self-review in `../docs/HOW_WE_WORK.md`. The first one
matters most: **can this check fail?** Prove it by planting the bug it should
catch.
