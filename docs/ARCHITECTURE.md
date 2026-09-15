# Karwan — architecture for four roles

The app is bigger than a single-purpose app: **customer, merchant, courier, admin**, across
**two demand types** (delivery and rides). Four audiences reading the same records
differently is what turns a clean codebase into a pile of conditionals. This document is how
we avoid that.

**The rule underneath all of it:** the same record, seen by four roles, is four different
things. Separate by role at every layer — routes, controllers, serializers, policies, screens
— and share only what is genuinely identical.

---

## Naming: get these right before there is data

| Use | Not | Why |
|---|---|---|
| **`merchants`** with a `kind` (`restaurant`, `store`, `pharmacy`) | `restaurants` | Hamma9900 has already said "restaurant **or store**". A store is not a restaurant. |
| **`catalog_categories` / `catalog_items`** | `menu_categories` / `menu_items` | A shop has products, not a menu. |
| **`courier`** | `rider` / `driver` | One human, one wallet, one commission — "rider" in the delivery UI, "driver" in the rides UI, `courier` in the model. |
| **`jobs`** as the shared concept; `orders` and `trips` as the two kinds | one table for both | An order has line items and one destination; a trip has two pins and no items. Never merge them. |
| **`payment_status`** | `cash_status` | Cash is one method, not the only one. |

Renaming any of these later means a migration with live orders in it. Renaming them today is
a `sed` and a green suite.

---

## Backend structure

**Namespace controllers by role.** This is the single most important decision in the whole
codebase:

```
app/controllers/api/v1/customer/...
app/controllers/api/v1/merchant/...
app/controllers/api/v1/courier/...
app/controllers/admin/...          # Administrate
```

One `OrdersController` serving three audiences with `if current_user.courier?` branches is
how this becomes unmaintainable. Three thin controllers beat one fat one, even with some
duplication — **duplication between roles is cheaper than coupling between roles**, because
the roles diverge over time and the conditionals never get removed.

**A serializer per role, not one with conditionals.** A courier sees the pickup address and
the cash to collect. The customer sees the courier's first name and an ETA. The merchant sees
neither. Same order, three shapes. Follow edu-safi's serializer discipline.

**A policy per role** (Pundit, as edu-safi does), and remember its hardest-won lesson:
**`current_organization` is tenancy, not permission.** edu-safi had five endpoints where the
correct scope existed, was correct, and was never consulted. Write the scope **and use it**,
and add a request spec proving both the refusal and the legitimate path.

**Service objects for anything with rules**, not fat models and not fat controllers:
- the job state machine and every transition
- dispatch (offer → deadline → next courier → admin)
- fare and fee calculation, reading Setting rows
- wallet entries and settlement

**Jobs for every timeout.** A state with no timeout is an order that sits forever.

---

## Mobile structure

**Copy edu-safi's shape — it already solved this for four roles.** Directory per role, all
business logic in screens, route files as thin wrappers:

```
src/screens/customer/   merchant/   courier/   shared/
src/components/ui/      # one primitive library, used by all roles
src/components/common/  # UniversalList, filters, selection
src/api/                # one file per domain
src/config/roles/       # per-role navigation config
```

**One list component for the whole app.** Hatiwal has `UniversalList`, edu-safi has
`UniversalIndex`. There will be many list screens across four roles, and hand-rolling each
one is precisely how Hatiwal reached 113 screens that each behave slightly differently. Build
it once, early, and forbid `FlatList` in feature screens.

**One primitive library, strictly.** edu-safi's rule is that every visible element comes from
its component library or a composition of them, and hand-rolling a button is a bug. That rule
is what keeps three deliberately-different role designs from becoming three incompatible
codebases. **The roles differ in layout, density and colour — not in components.**

**Per-role theming, shared components.** Customer warm and photo-led; merchant a high-contrast
workbench readable across a kitchen; courier huge targets, one action per screen, sunlight
legible. Achieve that with tokens and layout, not with three sets of buttons.

---

## The thing that will actually bite: active role

Four roles in one app means **every screen depends on which role is active**, and bugs there
are silent rather than loud.

edu-safi shipped exactly this: a stale stored session meant **every workspace test was
quietly measuring the admin** while claiming to test four different roles. Four test suites
were green and measuring the wrong thing.

So:
- The **active role is explicit state**, never inferred from what happens to be on screen
- **Assert it.** Every role-scoped test's first assertion is that the session really is that
  role. That one line is what caught the edu-safi bug.
- Switching roles **clears role-scoped caches.** A courier's job list must not survive into
  the customer tab.
- The backend **never trusts a client-supplied role** — it derives permission from the token.

---

## Refactoring discipline

- **Extract on the third occurrence, not the first.** Two similar screens are fine; three is a
  component.
- **Never share between roles just because the code looks alike.** Shared code that serves two
  roles becomes conditional code, then unmaintainable code. Share primitives, not features.
- **Delete rather than generalise.** A thing used once should be inlined, not parameterised.
- When a file passes ~300 lines, split it — edu-safi's rule, and it holds.
