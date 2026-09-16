# Identity, accounts, roles and sessions — the key flow

> **Status: BINDING, and Hamma9900 has said to respect it 1000%.** This is the spine of the
> platform. Every other document defers to it on anything about who a person is, what they can
> do, and how they get in. If a change would contradict this file, the change is wrong — bring
> it to Hamma9901 rather than working around it.

Read `CLAUDE.md` corrections 2, 9, 10, 15 and 18 alongside this. **Correction 2 is struck**
and correction 10's "no email, no password" no longer holds — §1 below replaces both, and the
reason is at the top of it.

---

## 1. One person, one account, two ways to name it

> **REWRITTEN 16 SEPT 2026.** This section used to say "no email, no password" and describe a
> phone-plus-OTP login. Hamma9900 struck that after seeing the code screen on a device:
> *"We will not use OTP. We will have login simple with email and password or phone number and
> password."* `CLAUDE.md` correction 2 is struck with it. The OTP machinery is **retained and
> switched off**, not deleted — see the end of this section.

### The argument that settles it, and it is not a UX argument

**Google Play requires an email address to publish an app at all.** So does the App Store.
Hamma9900 cannot ship Karwan to a single phone without holding a Google account, which means
**email was never avoidable for this platform** — it was only ever avoidable for its *users*.

That reframes the original reasoning, which was true and still reached the wrong conclusion.
"Many Afghan users have no email" is a fact about users; it was turned into "the system must
not have email", which does not follow. Once the owner is standing in a Google account in
order to publish, refusing a user the option of an email address is a restriction with
nothing behind it — and it costs the one identifier that works when a SIM is swapped, a
number is recycled, or a handset is shared.

And the second half of the original argument turned out to point the other way too. **An SMS
code is not the simplest login; it is the slowest one.** It needs a message to arrive on a
weak network, six digits read off a lock screen and typed into another app, inside five
minutes, and it costs real money per attempt — the single recurring per-unit cost in v0
(correction 6). A password in one field needs none of that and works with no signal at all
except the request itself. Correction 10 asks for **the simplest thing in the app**; that is
the requirement, and OTP was one reading of it rather than the requirement itself.

### The shape

```
users                       ← ONE row per human. TWO ways to name them, both unique.
  phone (NOT NULL, unique)     the GUARANTEED identifier
  email (nullable, unique)     the ADDITIONAL identifier — partial index, WHERE NOT NULL
  encrypted_password           Devise :database_authenticatable, bcrypt
  reset_password_token         Devise :recoverable
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

**Phone is the guaranteed identifier; email is the additional one.** The asymmetry is in the
schema, not in a comment:

- **`phone` is NOT NULL and unique.** Everyone has one, a courier has to be ringable, and a
  customer has to be reachable when the rider is at the wrong blue gate. Registration
  requires it.
- **`email` is nullable and unique.** Accepted, never required. Requiring it would lock out
  the two cases that are normal here and nowhere else: a **sideloaded APK** passed over
  Bluetooth or WhatsApp, whose owner may hold no Google account at all, and a **shared
  handset** whose Gmail belongs to somebody's brother. The app asks for both; the API refuses
  neither.
- The unique index on email is **partial — `WHERE email IS NOT NULL`**. Postgres already
  treats NULLs as distinct, but an empty *string* is not NULL, and two accounts saved with
  `email: ""` would collide on a plain index and be refused for no reason a user could
  understand. `presence` in `Users::RegistrationService` plus the partial index is what makes
  both things true at once: many accounts with no email, at most one per real address.

**One field on the screen, not two and not a toggle.** `Users::Identifier` resolves what was
typed by its shape — an `@` means email (downcased), anything else is normalised as a phone
number. Two fields is a decision the user has to make and a screen they can get wrong, and
`AFGHAN_UX.md` asks for the fewest taps and the fewest choices.

**Normalise before the uniqueness check, always.** `0700000801` and `+93700000801` are the
same phone. A uniqueness check on the raw string lets one person hold two accounts, which in
a cash business means two wallets and two credit lines. `PhoneNumbers.normalise` runs in a
`before_validation`, so there is no path that skips it.

### One failure for every wrong credential

`Users::PasswordSignInService` answers **`invalid_credentials`** for all of: no such account,
a deleted account, an account with no password yet, and a wrong password. Told apart, this
form is an **account-existence oracle** — type an address, learn whether that person uses
Karwan. In one Kabul neighbourhood where everyone knows everyone that is a real privacy leak
rather than a theoretical one, and the people most exposed by it are exactly the ones
`AFGHAN_UX.md` §7 is about.

The password is verified **even when no account was found**, against a decoy bcrypt digest,
because otherwise the *response time* is the oracle the shared message closes.

**The one case told apart is a SUSPENDED account** — 403 `account_unavailable` — because the
password was right. "Try again" would be a lie, and that person needs to ring support.

**The same rule applies to the reset door.** A login form and a reset form are two doors to
the same question, so `POST /auth/password_reset` answers identically whether or not the
account exists, and reports its channel from the *shape of what was typed* rather than from
the account.

### No verification step

Hamma9900: *"For now no authentication."* In context — he had just described the login — that
means no verification: no OTP, no emailed confirmation link. Register, set a password, you are
in, and `phone_verified_at` stays nil.

**What that costs, recorded rather than glossed:** a mistyped phone number reaches a courier
who then cannot ring the customer. The mitigation is operational rather than technical — the
courier is standing outside the address and calls, and support is a human with a phone number
in the app. It is a real cost and it is his call.

### OTP is retained, switched off, and has a new job

The table, the throttle, the SMS adapter and their tests are all built and all kept, behind
the `otp_sign_in_enabled` setting (default **false**). `Api::V1::Auth::OtpController` refuses
with `otp_disabled` rather than sending a message, because an SMS is the one real per-unit
cost in v0 and spending it on a flow no client drives is spending Hamma9900's money.

He said "for now", and it earned its keep: **a one-time code is now the password-RESET
channel**, which is what a one-time code is actually good for — rare, and where the friction
is the point rather than a tax on every login. See §5.

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
2. **`ApplicationPolicy`'s helpers and scopes read the authenticated user's own `user_roles`** —
   **never a header, a param or anything the client sends.** Four roles in one app is exactly
   the shape where a client-supplied role becomes privilege escalation. The **scopes** are the
   half that leaks quietly: a missing predicate is a 403 somebody notices, a missing scope is
   another courier's jobs on screen. `Api::V1::BaseController` runs `verify_authorized` and
   `verify_policy_scoped` as after_actions, so a controller that forgets Pundit raises on the
   way out rather than serving unfiltered data.

   **Do not gate capability on `active_role`.** That is which tab a device is showing, not what
   a person may do — and gating on it would break §6: a courier whose phone sits in the customer
   tab must still be able to work the job he is already carrying. Two methods that read like
   this gate — `current_role` and `require_role!` — existed with **no callers at all** and were
   deleted in `ec05764`. Dead code that looks like a guard is worse than no guard, because it
   stops the next person looking for the real one.
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

> **REWRITTEN 16 SEPT 2026** alongside §1. The mechanism is an identifier and a password; the
> doors either side of it are unchanged, because it was never the doors Hamma9900 objected to.

```
              ┌──────────────────────────────────────────┐
              │  one field: email OR phone   →  password  │  one mechanism, always
              │  resolved by SHAPE, not by a toggle       │
              └──────────────────┬───────────────────────┘
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

**One login mechanism, always.** Never a second flow per role. Three login paths would mean
three credential paths, three throttles and three copies of bugs already paid for once — and
one human holds one account, so a courier who also orders food would need two.

**Three endpoints, and they are three because a password forces it.** Under OTP, signing up
and signing in were the *same* action: possessing the phone was the proof, so a new number
created an account and a known one signed in. With a password they cannot be one — "sign me
in" needs the account to exist and "make me an account" needs a password to be chosen.
Folding them together means a mistyped digit silently registering a second account with its
own wallet.

| | What it is |
|---|---|
| `POST /api/v1/auth/registration` | make an account. Phone + password required, email optional, granted `customer` |
| `POST /api/v1/auth/session` | sign in. One identifier, one password |
| `POST` / `PUT /api/v1/auth/password_reset` | ask for a code, then spend it |

**Browse before login.** A first-time user sees restaurants before being asked for anything.
See correction 10 — that part of it stands unchanged.

### Forgotten password → a CODE, never a link

This is where the retained OTP machinery does its real job, and the shape is **forced by
correction 16: there is no web app**, so there is no page for a reset link to open.
`hatiwal-api/app/mailers/user_mailer.rb` sends a token in a URL on hatiwal.com; Karwan has
nowhere equivalent, and a deep link back into the app opened from a webview on a cheap
Android fails silently with no way to recover. So the person types a six-digit code into the
app, exactly as they would have typed a login code — once, when they have actually lost
something, rather than on every sign-in.

- **The code is always issued against `user.phone`**, whichever identifier was typed, because
  phone is the one key every account has. That also puts email resets behind the **same**
  counter that protects the SMS bill rather than behind a second one nobody tuned.
- **It is delivered on the channel the identifier named** — an `@` means the email, anything
  else means an SMS. So a user with no email is never told to check one.
- **The code is never returned in the response, in any environment.** `POST /auth/otp` does
  return its code outside production so the QA rig can drive a sign-in; doing the same here
  would mean anybody who can type an address takes over an account on any non-production
  deploy, and "it is only staging" is how that ships.
- **A code issued to one account cannot reset another.** The lookup is by the *resolved
  user's* phone, never by the phone that asked — otherwise anyone could reset the account of
  anyone whose email they know by requesting a code for their own number. It is the worst
  failure available in this flow and it has its own test.
- **Completing a reset revokes every other session.** A reset is what somebody does when they
  think another person has their password; leaving that person's token alive makes it
  theatre. On a shared handset (`AFGHAN_UX.md` §7) that person is often still holding the
  phone.
- **It signs them in on this device immediately, as `customer`.** Sending somebody who just
  proved they hold the phone back to the login screen to retype a password they set four
  seconds ago is a dead end for a user who is already frustrated — and a reset proves
  possession of a phone, which is not evidence that anybody approved them to carry cash.
- **The SMS is worded differently from the sign-in code, deliberately.** "Your code is
  123456" could mean either, and an ambiguous code SMS is exactly what a phishing message
  imitates. Somebody who did *not* ask for it has to be able to tell what it is for.

**Still blocked on Hamma9900, and it is the same blocker as before:** the SMS gateway. Phone
is the guaranteed identifier, so for most accounts the reset is an SMS — and no real Afghan
phone can receive one until he picks a provider. The email half works today once SMTP has its
four environment variables. That is a narrower gap than it was: an SMS gateway used to be
required to *log in at all*, and is now required only to *recover* an account.

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
2. A client-supplied role is ignored entirely — asserted against the policy layer that
   actually enforces it, not against a helper. (A test here once stayed green after the method
   it named was rewritten to trust `params[:role]`, because that method had no callers.)
3. Granting `courier` or `merchant_owner` also yields `customer`.
4. Assigning a merchant owner grants `merchant_owner`; unassigning revokes it.
5. Two sessions for one user hold two different active roles at the same time.
6. Switching role on one session does not change another session's role.
7. A courier with a live Order is refused a Trip offer, and vice versa — at **both** the offer
   and the accept path.
8. A suspended user's valid token stops working.
9. Choosing an unheld partner role returns the application path, not an error.

**Added with the password login (§1, §5), and each one has been planted and proven red:**

10. **An unknown identifier and a wrong password give the identical answer** — same status,
    same code, same message. The oracle rule, and the plant is to tell them apart.
11. **The same is true of the reset door**, whose response must not depend on whether the
    account exists.
12. **A local `07…` number and a `+937…` number are one account** — asserted at
    registration, at sign-in and in the seeds, because the check that matters happens
    *after* normalisation and the plant is to check the raw string.
13. **A second account may exist with no email**; one may not exist with a duplicate email.
14. **A code issued to one account cannot reset another.** The plant is to look up any live
    code rather than the resolved user's.
15. **Completing a reset revokes every other session** but not the one it just issued.
16. **The reset response never contains six digits**, in any environment.
17. **The seeded QA accounts can actually sign in through the live path** — asked of the
    sign-in service, not of the column, because "a hash is present" is not the claim. The
    switch from a code to a password made every seeded account unreachable in one commit and
    it would have presented as "the login is broken".
