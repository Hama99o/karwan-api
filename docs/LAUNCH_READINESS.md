# Launch readiness: what must be true before Karwan takes one real order with real money

Written 25 Sept 2026 at `b5ab84b`, as an **inventory, not a fix list**. Each
line says what is true now, how I know, and whose move it is. **Ours** means
code in this repo. **His** means Hamma9900's decision, account or money.
Where both halves exist, they are split.

The state this starts from: whole suite green, run detached (`92d5e2d`, seed
13225: EXIT 0, 3,162 examples, 0 failures, 3 pending). Brakeman, bundler-audit,
Zeitwerk and rubocop are clean. Nothing has ever been deployed: `KAMAL_HOST`
is blank, and there is no VPS.

---

## A · Blockers: a real order must not happen until these are true

| # | What | True now | Evidence | Whose |
|---|---|---|---|---|
| A1 | **Backups** | none. `bin/backup` and `bin/restore-check` are designed (RUNBOOK §9.1), not built | `ls bin` | **His** go-ahead and off-box storage (a few euros a month). **Ours** to build, about a day. The ledger is one-way door #4: entries lost are unrecoverable |
| A2 | **Somewhere to run** | no VPS, no domain | `deploy.yml` needs `KAMAL_HOST` and `KAMAL_PROXY_HOST` | **His** |
| A3 | ~~**TLS flags**~~ **DONE `616daac`**: assume_ssl, force_ssl and the /up exemption, proved at the production layer (a `secure` cookie, HSTS, /up 200; with assume_ssl planted off, a 301 loop). Was: both **commented out**, while hatiwal-api sets both | `config/environments/production.rb:25,28` | **Ours** (copy Hatiwal). Without them the console's session cookie isn't marked Secure, and there's no HSTS. kamal-proxy terminates TLS, but Rails doesn't know it |
| A4 | **A forgotten password on a phone-only account** | the only SMS adapter is `log`. In production a reset code by SMS **goes nowhere**, so a user with no email is locked out for good (the OTP flow too, if it is ever switched on). **And the words are English:** `password_reset_sms_body_ps/_fa` and `otp_sms_body_ps/_fa` all default to English, so the day a gateway connects, a Pashto speaker gets an English SMS. Four strings, sent to karwan-42's native-review batch | `Notifications::SmsClient::ADAPTERS` has one key; `bin/preflight` warns | **His**: choose the gateway (price per message to Afghan networks). **Ours**: one adapter class after that |
| A5 | **Push stops an hour after each deploy** | `FcmClient` sends a static `FCM_ACCESS_TOKEN` from the environment. HTTP v1 tokens minted from a service account expire after about an hour, and nothing refreshes them | `fcm_client.rb:31,70`; no googleauth/JWT anywhere | **His**: the Firebase project and service account. **Ours**: mint and refresh the token from the service-account key. ~~The merchant alarm has polling as its second channel, so this degrades rather than kills the alert~~ **CORRECTED 25 Sept 2026: that was only true in the foreground.** The in-app alarm and the board poll are foreground-only by design, and karwan-mobile has no background fetch or task manager at all (checked: no `expo-background-fetch`, `expo-task-manager` or `TaskManager` anywhere). So for a tablet that is backgrounded or locked, **push is the ONLY channel**, and it dies an hour after each deploy: a kitchen not looking at its tablet cannot learn an order arrived, nor afterwards that it lost one. It is still his decision (Firebase); what changes is its cost |
| A6 | **Seeing a failure**: **our half DONE** (see NOTES "WHERE AN ERROR GOES"): every error Rails reports is logged and then kept, redacted, counted and pruned, on the console's Errors page. A hosted service stays his choice. Was: | no error subscriber. A 500 on checkout exists only in container logs (`RAILS_LOG_TO_STDOUT`), which nobody tails | no `Rails.error.subscribe` in app/, config/ or lib/ | **Ours** to propose, **his** to choose. Correction 14 rules out a crash reporter that phones home, so the self-hosted shape is `Rails.error.subscribe`, written to a table and counted on the console, the way the router fallback is now |
| A7 | **Settings only he can fill** | `top_up_bank_name` and `top_up_account_number` are **empty**; `support_phone` is set in dev and must be the real number | `bin/preflight` "Settings only he can fill" | **His** |
| A8 | **One rehearsal on the real box** | never done: `db:prepare` building four databases, the reference seed with `ADMIN_PASSWORD`, OSRM data present, and `/up` healthy | nothing has been deployed | **Both**: his box, our runbook |
| A9 | **One order with real cash, end to end** | every step is covered by request specs (place → accept → pickup → deliver → commission → settle → reimburse), but no human has ever done it on the console with a real wallet | the specs | **Both**: the ops rehearsal. It is also the only test of the settlement screens as a person uses them |
| A10 | **A courier's identity documents** (national ID, selfie) | **do not yet meet the requirement below.** Found 25 Sept 2026 by karwan-42's privacy pass and confirmed by Hamma9901. The details are deliberately NOT recorded in this public repository until it's fixed; they are in karwan-mobile's private `docs/PRIVACY.draft.md` notes. **The requirement:** only an authorised office person may see a courier's documents, each view must require their signed-in session, any link must expire in minutes, and the app should not need a document URL at all (an authenticated endpoint can serve the bytes). Nobody is exposed today (there is no production); it must not ship as it is. **Take first when work resumes.** | **Ours** to design and build. **His** to answer who, beyond himself, may ever see these (downstream of the console-logins question) |

## B · Should be true, and cheap

| # | What | True now | Whose |
|---|---|---|---|
| B1 | **OSRM image pinned**: **DONE `f6322a8`** in this repo, by digest (v26.9.0). **karwan-map's build scripts still say `:latest`**, and they build the data. Was: `osrm-backend:latest`. The `.osrm` files are built by one version's `osrm-extract` and must be served by the same version. A pull of a newer `latest` can refuse them, and every fare then falls back to straight line (visible since `6ae3009`, but priced wrong until someone looks) | **Ours** |
| B2 | **OSRM data on the host** | `/var/karwan/osrm` must be built before the accessory starts (RUNBOOK) | **Both** |
| B3 | **SMTP** | secrets are declared (`deploy.yml`); no provider chosen. Email reset and mail depend on it. **What keeps the email channel honest on a real box:** `bin/preflight` FAILS a deployed box with no `SMTP_ADDRESS`. But preflight is run BY HAND (the RUNBOOK says "run it first"); no Kamal pre-deploy hook calls it. So the guard holds only if somebody runs it. A `.kamal/hooks/pre-deploy` running it would make that automatic, and is deploy config: his. Since `58b8b31` the API itself never claims an email was sent through an unconfigured SMTP, whatever the box | **His** |
| B4 | ~~**Cable database**~~ **DONE**: `db/cable_schema.rb` (the gem's template, identical to hatiwal-api's). A production `db:prepare` now builds `solid_cable_messages`. A gate enumerates every production database in database.yml and requires a schema for each | **Ours** |
| B5 | **Correction 3 in `CLAUDE.md`** | now TRUE: cache, queue and cable all run on Postgres with their schemas | **His** (I don't edit CLAUDE.md on a peer's word) |
| B6 | **Audit logs copy personal data** (full before/after values, so ID numbers and guarantor phones land in `audit_logs`), and the table has no retention | recorded, not built (queued) | **Ours** |
| B7 | **"Deleting" an account is a soft delete, deliberately** (one-way door 6: records with live history are kept) | correct as built; so the privacy policy and Play's data-safety form must not say data is deleted | **His** wording, karwan-42's draft |

## C · Decisions still open that touch real money (his; recorded, not built)

- The detour cap, and who pays if a fee is capped.
- A maximum delivery distance from the shop (only the country is enforced).
- The ride fare rule: honour the SHOWN fare exactly, or refuse-if-higher as with food.
- Whether a fare priced by straight line during a router outage is repriced afterwards.
- Console logins: will anyone else hold one? That decides whether 106 console actions need policies (104 before the Errors page).
- The three pending specs are the two open money decisions plus one empty design spec.
- CLAUDE.md's standing open questions: the bank or HesabPay account, and the trusted person in Kabul.

## D · Checked, and NOT a blocker

- **The 2,019 seeded orders in a shape the product never makes are dev-only.**
  `db/seeds.rb` refuses sample and e2e data in production, so they can't
  reach a real database. They still distort any dev measurement over orders.
- **Rate limits survive a deploy** (`b5ab84b`), proven at the production
  layer, and count per identifier with per-IP backstops (`93e4f66`, `6703d8b`).
- **Secrets** are all read from the environment in `.kamal/secrets`, and
  `config/master.key` is not in git.
- **The production admin** can't be seeded with a default password: the seed
  raises without `ADMIN_PASSWORD`.
- **Router outages are visible** on the reports page (`6ae3009`).

## The order I would take these in (refreshed 25 Sept 2026, at the pause)

Done since this was written: A3 (TLS), B1 (OSRM pinned, in both repos), B4
(cable schema), and our half of A6 (errors kept on the console). **Ours,
next: A10** (courier identity documents, by the requirement above), then B6
(audit-log retention). A5's code half waits on Firebase existing; A1 (backups)
waits on his go. A2, A7, A8 and A9 are the launch itself, and are his.
