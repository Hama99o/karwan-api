# Karwan — Product detail (v0)

Read `CLAUDE.md` first. This is the screen-level spec. **V0 is simple and functional** —
where this document and that instruction conflict, cut the feature.

---

> **PLATFORM NOTE:** the app is **Karwan**, one app carrying **two demand types** — food
> delivery and rides — on one courier pool, one wallet, one dispatch, one admin. The screens
> below are the **food** product, which ships first. Rides add roughly ten screens, a `trips`
> table and a fare calculator; the schema is being shaped now so that is an addition rather
> than a rewrite. **Do not build the ride product yet.** "Karwan" may survive as the
> name of the food section — Hamma9900's call.

## Build phases — build in this order

**Do not jump ahead.** Each phase makes the next testable.

| Phase | What | Why this order |
|---|---|---|
| **0** | API skeleton + v0 data model (migrations, models, factories) | Everything depends on the schema |
| **1** | **Admin console + seed data** | You cannot test an order without a restaurant and a menu, and you cannot operate without being able to see and fix. Admin first is correct for an ops business. |
| **2** | Customer: browse → cart → place order (happy path only) | The demand side proves the schema |
| **3** | Restaurant: incoming alert → accept → mark ready | Closes the loop to a real kitchen |
| **4** | Rider: offer → accept → pickup → deliver + collect cash | The physical flow |
| **5** | Wallet, top-ups, settlement, reconciliation | The money, once orders exist to charge for |
| **6** | Live tracking + ETA, offline tiles | Nice-to-have that becomes necessary at volume |
| **7** | Per-role polish, i18n completeness, RTL, empty/loading/error states | Last, because it applies to finished screens |

---

## Customer

**Onboarding** — phone number + OTP. Language picker (ps / fa / en) **before** anything
else; default from device locale. Ask for location permission with a reason, not a bare prompt.

**Home** — list of restaurants. Each card: name, photo, **open/closed**, prep time,
distance, rough ETA. Closed restaurants shown but not orderable, greyed with their next
opening time. Search by name. No filters in v0 beyond open-now.

**Restaurant screen** — menu grouped by category. Item row: name, price, photo, sold-out
state. Tapping an item opens options (size, extras) with price deltas, quantity, and a note
field.

**Cart** — line items with their chosen options, subtotal, delivery fee, **total in AFN**,
and the three delivery fields:
- **a pin on the map**, dropped by the customer
- **a landmark note** ("blue gate near Shar-e-Naw park, second floor")
- **a phone number**, pre-filled, editable

**Place order** → a status screen that shows the state machine plainly: *waiting for the
restaurant → preparing → ready → on the way → delivered*. Each with a timestamp. Once
picked up, the rider's position on the map.

**Amount to pay in cash, shown prominently**, with a note if change will be needed.

**Order history** — past orders, itemised, re-orderable.

**Profile** — name, phone, saved pins with labels, language, **role switch** if they hold
another role.

---

## Restaurant

Not self-serve in v0 — **admin onboards restaurants.** Their app is a workbench, not a shop.

**The single most important control: open / closed.** Large, unmissable, on every screen.
A restaurant marked open that isn't is the most damaging state in the system.

**Incoming order** — full-screen, **loud and repeating until acknowledged**. Assume a cheap
tablet propped on a counter in a noisy kitchen. Accept, or reject **with a reason** from a
fixed list (out of stock / too busy / closing / other).

**Order board** — columns or sections: new, preparing, ready, picked up. Each shows items,
options, notes, and age. **Mark ready** is the main action.

**Menu management** — categories, items, price, photo, prep time, and a **sold-out toggle**
that must be reachable in one tap from the order board, because it gets used mid-rush.

**Today** — orders, items sold, cash received from riders, our commission. No charts.

Design: big touch targets, high contrast, readable across a room, minimal chrome.

---

## Rider

Admin onboards riders and sets the wallet credit line. Used one-handed, in motion, in sunlight.

**Available / offline** toggle — the first thing on screen.

**Offer** — a card with a countdown: restaurant name and distance, customer distance,
**the food cost they must advance**, their fee, and whether their **wallet can fund it**.
Accept or decline. Decline needs no reason.

**Active order** — a single screen that changes with state:
1. Navigate to the restaurant (map + address + phone)
2. **Confirm paid the restaurant** — shows the exact amount, food total minus our commission
3. Navigate to the customer (pin + landmark note + phone, all tappable)
4. **Collect cash** — shows the exact amount and change required
5. Confirm delivered

Problem buttons at every step: *customer not answering*, *customer refused*, *restaurant not
ready*, *call support*. Each one records a reason and reaches admin.

**Wallet** — balance, credit line, recent entries, and **top-up instructions showing their
own 4-digit reference code**. Warn clearly as the balance nears zero, because at zero they
stop earning.

**Today** — deliveries, earnings, cash currently in hand.

Design: high contrast, enormous buttons, almost no text, one action per screen.

---

## Admin — the ops console

This is the most important surface in v0. It is what makes the business operable while
everything else is half-built.

**Live order board** — every order, its state, its **age**, who is on it. Colour by
staleness: an order sitting in one state too long turns red. This is the screen someone
watches all evening.

**Intervene on any order** — reassign the rider, cancel, mark failed with a reason, credit a
wallet, adjust an amount. **Every action logged with who did it.**

**Restaurants** — create, edit, set commission rate, open/close on their behalf, manage
their menu when they can't.

**Riders** — create, set credit line, view wallet, **record a top-up** (match a bank deposit
by the rider's 4-digit code), view cash in hand.

**Settlements** — expected vs **counted**, both stored, plus the named person who counted.

**Config** — commission %, delivery fee, rider fee, cash-in-hand limit, default credit line,
ETA average speed. Editable, no deploy.

**Reports** — orders per day, revenue, commission earned, rider utilisation (orders per
rider per day — the number that decides the business), failure reasons ranked.

**Audit log** — searchable, everything money-touching and every intervention.

---

## Cross-cutting

**Role switching** — one account, several roles, obvious and fast, remembers the last role.
Each role's design is deliberately different; this is a stated product decision, not an
accident to be tidied up.

**Languages** — Pashto, Dari, English. RTL for ps and fa. Use **logical** spacing utilities
and mirror directional icons. Pashto and Dari strings run longer than English; layouts that
pass in English will break.

**Notifications** — never rely on one mechanism for the restaurant alert. Push, plus in-app
polling while open, plus an SMS or phone path. A missed alert is a lost order.

**Support** — a phone number in the app for all three roles. Delivery is an operations
business with an app attached.

**Money display** — AFN, never a hardcoded symbol, never summed across currencies, and
**never totalled on the client from whatever page happened to load**. edu-safi shipped that
bug three times today; the endpoint sends the totals.
