# Karwan — how the mobile app looks

Read `AFGHAN_UX.md` first. Everything here is downstream of it: a large share of users cannot
read fluently, two of three locales are right-to-left, and the phone is cheap with expensive
data. **Those facts decide the design; taste only fills in what's left.**

---

## The structural decision: one component library, three modes

The four roles look **deliberately different** — Hamma9900's instruction — but that difference
comes from **layout, density and colour, never from different components.** Three sets of
buttons is three codebases.

| Role | Feel | Navigation |
|---|---|---|
| **Customer** | warm, roomy, photo-led — the most polished surface | bottom tabs: Home · Search · Orders · Profile |
| **Merchant** | a workbench, not a shop. Dense, high-contrast, readable across a noisy kitchen from a metre away | **one screen** — the order board. Catalog and settings behind a single icon. No tabs. |
| **Courier** | one-handed, in motion, in sunlight. Huge targets, one action per screen, almost no text | **one screen** — the current job, or the availability toggle. Nothing competing. |
| **Admin** | web only (Administrate) | — |

**Why merchant and courier get no tabs:** tabs invite browsing. Both are working, not browsing.
A courier holding a phone at a junction needs exactly one thing on screen.

---

## Design RTL-first

Two of three locales are right-to-left. **Design in Pashto or Dari and check English**, not the
other way round. Every team that designs LTR and retrofits ships mirrored bugs — Hatiwal shipped
a progress bar running backwards in three languages, and edu-safi needed 34 physical→logical
spacing fixes in one pass.

- **Logical properties only** — start/end, never left/right
- **Mirror directional icons** — chevrons, back arrows, progress. A correct `dir` with a
  left-pointing "next" arrow is still wrong.
- **Phone numbers and order codes stay LTR** even inside RTL text
- Pashto and Dari strings run **longer** than English; every layout that passes in English
  must be re-checked

---

## Colour — RECOMMENDATION, Hamma9900's call

**Lapis blue as primary, saffron amber as accent.**

Afghanistan is the historic source of **lapis lazuli** — the Sar-e-Sang mines in Badakhshan
supplied it to the ancient world. It is a genuinely Afghan colour with real provenance, it
reads as trustworthy (which matters in a market short on trust in institutions), and it is
nothing like the neon greens and pinks of Western delivery apps.

```
primary     #1B3A6B   deep lapis      — brand, headers, primary actions
primary-lo  #2E5A9E   lighter lapis   — pressed states, links
accent      #E8A33D   saffron amber   — CTAs, prices, "collect cash"
ink         #1A1D21   near-black      — text
surface     #FAF8F4   warm off-white  — page ground (not cold grey)
ok/warn/bad #2F7D53 / #B7791F / #B03A2E
```

Per-role tinting, same palette: **customer** leads with the warm ground and amber CTAs;
**courier** goes high-contrast, near-black on amber for the primary action so it survives
sunlight; **merchant** stays mostly neutral so the order states carry the colour.

*Alternative if you want warmer overall:* flip it — saffron primary, lapis accent. More
appetising for food, less credible for carrying passengers and money. I'd keep blue primary
because Karwan carries people and cash, not only dinner.

## Typography — RECOMMENDATION, Hamma9900's call

**Vazirmatn** throughout — open source, purpose-built for Persian/Dari, renders Arabic script
properly, includes Latin, variable weights. One family, four weights.

Do **not** reuse Madares' Rubik + Zain: it's a proven pair, but Karwan should not look like
another of his apps.

Numerals render **per locale** — Eastern Arabic (۰۱۲۳۴۵۶۷۸۹) in ps/fa, Latin in en — solved
once in the localisation layer alongside currency and the Shamsi calendar.

---

## The rules that come from literacy, not taste

- **Photos are the interface.** Every merchant and every catalog item has a large real photo.
  A photo sells and explains where a description cannot.
- **Icons always with labels.** An unlabelled icon is a guess; a bare label is unreadable to
  some users. Always both.
- **Numbers big.** Price, quantity, minutes, distance — the load-bearing information.
- **No paragraphs.** If a screen needs one, the screen is wrong.
- **A tappable phone number on every screen, every role.** The fallback that always works.
- **Touch targets 48dp minimum, 64dp for the courier's primary action.**
- **Test at 360dp on the oldest Android available** — not the newest.

---

## Cards, not lists

For merchants and catalog items: a **photo card** with the name, price and one state badge
(open/closed, sold out). Not a text row. A text row is a literacy tax.

Lists of *orders* are different — those are data, so a dense row with a state stripe down the
side is right, and the stripe carries the state in **form as well as colour** for the
colour-blind and for sunlight.

## Motion: almost none

Cheap phones, and animation reads as lag when the device is slow. Transitions only where they
explain a relationship — a sheet rising from the button that opened it. Nothing decorative.

## Every screen has an offline state

Not a spinner. Show the last known data with a quiet "not updated" marker. Data costs the user
real money, so never re-fetch what you already have.

---

## THREE DECISIONS FOR HAMMA9900

1. **Lapis blue primary + saffron accent**, or flipped (saffron primary)?
2. **Vazirmatn** as the single font family — yes or a different one?
3. **The demand-type switch on the customer Home** — Food / Ride / Send. Segmented control at
   the top of one Home screen, or separate bottom tabs per type? *Recommendation: segmented
   control, because it keeps one Home and one search, and adding a fourth type later costs a
   segment rather than a tab.*

---

# How it works — one order, three phones

The clearest way to hold this design in your head. Same order, 450 AFN of food, seen from
each role. **If a screen is not in this walkthrough, it is not in v0.**

## Customer — five taps to an order

1. **Home.** Photo cards of nearby merchants. Each: photo, name, open/closed badge, ETA,
   distance. No filter bar, no categories, no carousel. Tap one.
2. **Merchant.** Items as photo cards grouped by category. Tap an item → a sheet with
   quantity (− 1 +, big), options if any, a note field. **Add.**
3. **Cart.** Lines with prices, then the delivery block: the **map pin** (remembered from
   last time, tap to move), a **landmark voice note** (hold to record — the highest-value
   feature in the app), the phone number pre-filled. Then one button: **Order.**
4. **Status.** Five steps down the screen, each stamping a time as it happens:
   *sent → accepted → preparing → on the way → delivered*. At the top, the only number that
   matters: **Pay 450 AFN in cash.** Under it, "have change for 500" if the total is awkward.
5. **After pickup** the rider appears on the map with his name and a tappable phone number.

That is the whole customer app plus Orders and Profile. Nothing else.

**No typed address.** A pin plus a voice note. Kabul has no reliable street addressing and
the customer may not write fluently — so don't ask them to.

## Merchant — the board is the app

A cheap tablet propped on a counter. **There is no navigation.** The order board is the
default and only screen; the catalog and settings sit behind one icon.

- **Open / Closed** is pinned to the top of every screen, always visible, hard to hit by
  accident. A merchant marked open who is closed is the most damaging state in the system.
- **A new order takes over the whole screen** with a repeating sound until someone touches
  it. Two buttons: **Accept**, or **Reject** with a reason from a fixed list. Assume a noisy
  kitchen and nobody watching the screen.
- Accepted orders sit in the board with an **age counter that turns amber then red.** One
  action on each card: **Ready.**
- **Sold out** is one tap from the board, never buried in the catalog — it gets used mid-rush.
- When the rider arrives: **confirm he paid 405 AFN** (the food total minus commission).

## Rider — one screen, one button, one hand

- **Home is a single Available / Offline switch.** Nothing else competes with it.
- **An offer** arrives as a card with a countdown ring: pickup distance, drop distance,
  **"you advance 405"**, **"you earn 60"**, and whether his wallet can fund it. Accept, or
  decline with no reason needed.
- **One offer at a time — never a list to choose from.** A list requires reading and
  comparing, and it invites cherry-picking that starves the far orders. The dispatcher picks;
  the rider accepts or declines.
- **The active job is one screen that changes with its state,** one big button at each step:
  1. Navigate to the merchant — map, name, tappable phone
  2. **I paid 405** — the exact number, nothing to calculate
  3. Navigate to the customer — pin, the landmark voice note playable, tappable phone
  4. **Collected 450** — with the change note
  5. **Delivered**
- A **Problem** button in the same corner at every step: customer not answering, customer
  refused, merchant not ready, call support. Each records a reason and reaches admin.
- **Wallet**: balance, credit line, and his own **4-digit top-up reference code**. Warn loudly
  as it nears zero, because at zero he stops earning.

## What makes these three feel different

Same components throughout. What changes:

| | Customer | Merchant | Courier |
|---|---|---|---|
| Density | roomy | dense | one thing |
| Photos | everywhere | thumbnails | none |
| Text | short labels | data | almost none |
| Buttons | normal | many, medium | one, enormous |
| Navigation | 4 tabs | none | none |
| Read at | arm's length | a metre, noisy | a glance, moving |

## Role switching

One account can hold several roles. The switch lives in Profile, is obvious, and remembers
the last role used. **Because the three modes look so different, the user always knows which
one they are in** — which is the real reason the difference is a product decision and not an
inconsistency to tidy up. edu-safi's stale active-role session meant every test measured the
wrong user; make the current role visible, always.

## Two rules that hold across all three

- **Every money number is shown before it is owed.** The customer sees the total before
  ordering; the rider sees what he advances before accepting; the merchant sees the
  commission before confirming. Nobody is ever surprised by a number.
- **Every screen works offline** by showing last-known data with a quiet "not updated" mark.
  Never a spinner where data already exists — data costs the user real money.

---

# One library, a different design per workspace — the mechanism

Hamma9900: *"the library will be same but the design will be changed for each workspace."*
Workspace means role mode: customer, merchant, courier. This is how that works without
rotting, and the wrong ways are both common.

**Wrong way 1 — a component set per role.** Three Buttons is three codebases, three sets of
bugs, and a fix that lands in one place out of three.

**Wrong way 2 — components that branch on role.** `if (role === 'courier')` inside `button.tsx`
means every primitive knows about every role, a fourth role edits every file, and the courier's
size rules leak into the customer's code. This is the trap, because it looks harmless in the
first component.

**The right way — the role supplies token VALUES; components only know token NAMES.**

Each role's route group wraps its subtree in a theme at the boundary:

```
app/(customer)/_layout.tsx   → CustomerTheme  → tokens
app/(merchant)/_layout.tsx   → MerchantTheme  → tokens
app/(courier)/_layout.tsx    → CourierTheme   → tokens
```

`button.tsx` reads `color-primary`, `space-control`, `text-action`, `radius-control`. It never
reads a role. It cannot, because it is not passed one. **Adding a fourth role is one new token
file and zero component edits** — that is the test of whether this is built correctly.

## Hatiwal already solved this mechanism — extend it, do not invent it

`hatiwal-mobile` has `src/stores/theme.store.ts` and `src/hooks/useColors.ts` for light and
dark. That is the same problem with one axis. Karwan has two axes: **role × colour scheme**.
So six token sets, one mechanism, and the mechanism is already tested in production. Read those
two files before writing anything.

## The detail that will bite: theme SIZE, not just colour

Most theme systems carry colour only. Ours cannot, because the roles differ mostly in **size
and density**:

| Token | Customer | Merchant | Courier |
|---|---|---|---|
| `space-screen` | roomy | dense | roomy |
| `space-control` | normal | tight | generous |
| `size-touch-min` | 48dp | 48dp | **64dp** |
| `text-action` | normal | normal | **large** |
| `text-data` | normal | **large** | large |
| `radius-control` | soft | square | soft |

If the token set is colour-only, the first time the courier needs a 64dp button somebody will
write `role === 'courier'` inside a primitive, and wrong way 2 is in the codebase for good.
**So the token set includes spacing, radius, font size and touch target from the first commit,
even while all three roles still share most values.**

Colour is the *smallest* part of what changes between these three. Say that out loud when
building the token file, because it is the opposite of how a theme is usually shaped.

## What must stay identical across roles

Not just the components — the **behaviour**. A state badge means the same thing everywhere, a
money amount formats the same way, an offline marker looks the same, a tappable phone number
behaves the same. A courier and a merchant looking at the same order must not have to translate
between two visual languages to talk to each other on the phone. **Different density, same
meaning.**
