# Identity, accounts, roles and sessions — the key flow

> **Status: BINDING, and Hamma9900 has said to respect it 1000%.** This is the spine of the
> platform. Every other document defers to it on anything about who a person is, what they can
> do, and how they get in. If a change would contradict this file, the change is wrong — bring
> it to Hamma9901 rather than working around it.

Read `CLAUDE.md` corrections 2, 9, 10, 15 and 18 alongside this.

---

## 1. One person, one phone, one account

```
users                       ← ONE row per human. Identity = phone, unique index.
  phone (unique)               No email. No password. No username.
  name, locale, status
      │
      ├── user_roles        ← one row per role this human HOLDS
      │     customer
      │     courier
      │     merchant_owner
      │     admin
      │
      └── user_sessions     ← one row per DEVICE signed in
            device_name, platform, token_digest
            active_role     ← which role THIS device is using
```

**The phone number is the identity.** Not an email — in Afghanistan many users have none, and
it is one more thing to type on a bad connection. Email exists in exactly one place in this
platform: `admin_users`, a separate table for a browser login with a password, so that no
customer or courier token can ever reach an admin screen.

**Why one account and not four.** A courier orders food. A restaurant owner takes taxis. They
are one human with several capabilities, and the platform must always know it:

- **One wallet.** A courier's prepaid balance is one balance. Two accounts would mean a courier
  blocked from food work while holding credit for rides — the exact failure
  `CourierProfile`'s comment warns about.
- **One courier pool.** Utilisation across food and rides is the number this business turns on.
  Separate identities means separate pools and the thesis collapses.
- **One history, one status.** Suspend a person and they are suspended everywhere.

---

## 2. The four roles

| Role | Who | How granted |
|---|---|---|
| `customer` | anyone with a phone | **automatic**, on first sign-in |
| `courier` | vetted: identity, guarantor, documents | application → **human approval** |
| `merchant_owner` | a shop or restaurant | **admin onboards**, not self-serve in v0 |
| `admin` | ops staff | `admin_users`, browser only, never in the mobile app |

`admin` is deliberately absent from the mobile app. Nothing that can credit a wallet or cancel
an order exists on a phone that gets shared or lost — see §7.

---

## 3. The asymmetry — the rule most likely to be broken by accident

**Partner → customer is FREE AND AUTOMATIC.** Hamma9900: *"the client account open if we have
restaurant or rider or driver account automatic, because it's not a big thing."* Granting any
role must ensure `customer` alongside it, in the same transaction.

Not "it happens anyway because everyone signs in" — that is true today and true by accident of
the path. A courier created by a seed, by admin, or by any future import must still be able to
order food, or the shared-pool premise breaks silently.

**Customer → partner is NEVER automatic.** Hamma9900: *"when we create client, we can't give
access to create account as rider."* A person holding only `customer` cannot sign in as a
partner, cannot switch to one, and cannot reach a partner endpoint. Three things enforce this
and all three must stay true:

1. `switch_role!` refuses a role the user does not hold.
2. `Authenticatable#current_role` derives the role from the user's own `user_roles` — **never
   from a header, a param or anything the client sends.** Four roles in one app is exactly the
   shape where a client-supplied role becomes privilege escalation.
3. Each role's controllers live in their own namespace with their own policy.

**Granting a role is a write that must leave a trace.** An approval names its approver
(`verified_by` for an API actor, `verified_by_admin_user` for a console operator) and writes an
audit row. "Who let this person in?" must be answerable from the row.

**Revocation is the mirror and is easy to forget.** Unassigning a merchant's owner must revoke
`merchant_owner`, or a former owner keeps access to a restaurant that is no longer theirs.
Rejecting or suspending a courier must stop dispatch considering them.

---

## 4. Sessions: the active role belongs to the DEVICE

`active_role` lives on `user_sessions`, **not on `users`**. This is not a detail — it is what
makes Hamma9900's requirement possible:

> *"I should be able to login only one at a time [per phone], or with different mobiles I
> should be able to login all 3 — one for client, one for rider, one for restaurant."*

- **One session has one active role** → one phone is one role at a time.
- **Sessions are independent** → three phones hold three roles simultaneously.

With `active_role` on `users`, switching role on one phone would silently change it on every
other — one human, one role, everywhere at once. edu-safi shipped that exact bug, where a
stale active role meant every test measured the wrong user.

It also means **revoking a device revokes its role state with it.** A courier who loses his
phone leaves no courier-shaped session behind.

---

## 5. The login flow

```
                    ┌──────────────────────────┐
                    │  phone  →  OTP  →  in    │   one mechanism, always
                    └────────────┬─────────────┘
                                 │
              ┌──────────────────┴──────────────────┐
              │                                     │
     [ default, never asked ]            [ "Sign in as partner" ]
              │                                     │
          CUSTOMER                    ┌──────────────┼──────────────┐
                                      │              │              │
                                 restaurant       rider          driver
                                   /store       (delivery)       (ride)
```

**Customer is the default and is never asked.** Asking "what are you?" of somebody who wants a
kebab is a question that loses users. The partner path is a second, quieter action.

**One login mechanism, always: phone + OTP.** Never a second flow per role. Three login paths
would mean three OTP paths, three throttles, three SMS bills and three copies of bugs already
paid for once — and the phone number is the identity, so one human would need three phones.

**Browse before login.** A first-time user sees restaurants before being asked for anything;
the phone number is requested at the cart. See correction 10.

### Picking a role you do not hold → the FORM, never an error

Hamma9900: *"when they try to login tell to create account... they have different form to
submit."*

| Chosen | What happens |
|---|---|
| **rider / driver** | the courier application — identity, guarantor, documents, then waits for approval |
| **restaurant / store** | collects a phone and a name; **Hamma9900 calls them.** Not self-serve in v0 |

Both are "we will get back to you". **Neither is a dead end and neither is an error state.**
The courier application endpoint exists on the API and, before this flow, had no entrance from
the app at all — this is its front door.

---

## 6. Two phones, and why the guard is on the job

A courier may sign in on two phones — one watching deliveries, one watching rides — and take
whichever offer comes first. Hamma9900 asked for this explicitly.

**The server enforces one LIVE JOB per courier, regardless of how many devices he holds.** One
human, one vehicle, one place at a time; the server is the only thing that knows it.

Guarding the job rather than the device is deliberate and load-bearing:

- Two sessions become harmless, so his two-phone setup works.
- A courier whose phone dies mid-shift can sign in on another — a real event on a cheap Android.
- Without it, two phones hand him a delivery and a ride at once and **one customer always
  loses**: food goes cold while he drives a passenger, or a passenger waits at a kerb.

Note one phone already does both: `accepted_job_kinds` is an array, so a courier holding
`["delivery", "ride"]` is offered whichever comes up. Two phones are a preference, not a
requirement — nothing breaks for a courier who owns one.

---

## 7. Edge cases that must behave

- **Shared phones** (`AFGHAN_UX.md` §7 — not hypothetical in Kabul). Choosing a money-handling
  role at sign-in is the gate. Switching into one mid-session needs re-authentication, because
  the wallet, the top-up code and "close the restaurant" are the most damaging things a stranger
  holding an unlocked phone can reach.
- **A suspended account holding a valid token stops working immediately** — already enforced in
  `Authenticatable`.
- **A revoked or unreachable session lands on signed-out**, which is the safe direction.
- **`unknown` is a real third state**, not a convenience: a launch that holds a token and does
  not yet know whether it is good. Collapsing it either way gives every returning user a
  sign-in flash, or role screens that 401.
- **A merchant is currently ONE person.** `merchants.owner_id` is a single user, so a restaurant
  with staff means everyone uses the owner's account and the audit trail names the owner. Known
  limitation, additive to fix later with a `merchant_staff` join table. Recorded in NOTES.md.

---

## 8. Separability — one app now, four possible later

See correction 18. **The mobile apps may split; the backend and the identity never do.**

The test for every change: **could this role's screens be lifted into their own app tomorrow,
changing only the entry point?**

- **Shared and safe:** primitives, theme tokens, i18n, HTTP client, auth/session store, map.
- **Never shared:** screens, flows, role stores, role API modules. No shared module branches on
  role; no screen imports another role's screen.
- The API namespaces (`customers/`, `merchants/`, `couriers/`, `public/`) and the route groups
  (`(customer)/`, `(merchant)/`, `(courier)/`) **are the seams a split would cut along.** Keep
  them strictly separate.

Uber, Grab and Gojek all run one backend behind separate rider, driver and merchant apps. This
is that shape, before it is needed.

---

## 9. The tests that must exist, and must be able to go red

Each of these encodes a rule above. Prove each one fails by planting the bug back.

1. A user holding only `customer` is refused every partner role — switch, and endpoint.
2. `current_role` ignores a client-supplied role entirely.
3. Granting `courier` or `merchant_owner` also yields `customer`.
4. Assigning a merchant owner grants `merchant_owner`; unassigning revokes it.
5. Two sessions for one user hold two different active roles at the same time.
6. Switching role on one session does not change another session's role.
7. A courier with a live Order is refused a Trip offer, and vice versa — at **both** the offer
   and the accept path.
8. A suspended user's valid token stops working.
9. Choosing an unheld partner role returns the application path, not an error.
