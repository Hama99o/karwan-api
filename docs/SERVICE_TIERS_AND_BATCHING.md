# Service tiers, consent and batching

> **Status: BINDING.** Hamma9900's design, given 16 Sept 2026. Read with `CLAUDE.md`
> correction 19 (multi-job must not be foreclosed) and `docs/IDENTITY_AND_ROLES.md` §6
> (one live job per courier).

---

## 1. The customer chooses the tier, and that choice IS the consent

The single most important idea here. Batching is not something we do to a customer behind their
back — **it is something they agree to in exchange for a lower price.**

| Tier | Price | What the courier may carry |
|---|---|---|
| **Premium** | more expensive | **that order alone.** Nothing else on the run |
| **Normal** | cheaper | **up to N other orders** (start at 3 total, a `Setting`) |

Same shape for rides: a passenger choosing the cheaper tier consents to **another passenger
sharing the car**; premium means the car is theirs.

**This solves the problem batching otherwise creates.** A customer who paid a normal fare and
waited longer because the courier collected two other orders has no complaint — they chose it
and paid less. A premium customer is never batched, so there is nothing to explain.

### The consequence that decides the build order

**Consent cannot be retrofitted.** You cannot ask a past customer whether their completed order
could have been shared. So:

- **The tier ships in v0**, even though batching itself does not: it is a column on the order
  and the trip, an input to the quote, and a line on the cart.
- **The batching logic ships later**, when there is enough concurrent demand for it to fire.

Getting these two in the wrong order is the expensive mistake. A tier without batching is a
price difference that costs nothing to honour — we simply never batch. Batching without a tier
recorded per order is unshippable, because every existing order's consent is unknown.

## 2. The courier sees the tier BEFORE accepting

Hamma9900: *"same for rider, they should check before accepting, they should see if other
customers are allowed or not."*

So the offer card carries it. A courier deciding whether to accept needs to know whether this
run can be combined with another — it changes what the job is worth to him and whether it is
worth riding across town for. **Premium must be visibly premium on the offer**, because a job
he cannot combine is a job he may reasonably decline at the same fee.

## 3. Capacity has three axes, not one

Dispatch already refuses on cargo size (`:vehicle_too_small`). Two more join it:

| Axis | Source | Refuses when |
|---|---|---|
| **Cargo size** | `catalog_items.size_class`, max over the order, frozen | a bed on a bicycle |
| **Seats** | seat count per vehicle class | four passengers in a rishka |
| **Batch room** | tier + how much the courier already carries | a premium order onto a loaded run |

**Seat counts come from Hamma9900, not from a guess** — as with the cargo ordering. Later they
may come from the vehicle itself rather than its class: *"for vehicle we will see how many seats
they have, we will do the calculation based on this."* So the seat count is a property to be
recorded **at application**, with the class as its default.

## 4. Batch room will be customised per vehicle

*"we will see later we will customize it like by vehicle, if they have a place we can do more."*

So the "up to 3" is a starting default, not the model. The model is **capacity per vehicle**: a
zarang carries more parcels than a motorbike, so its batch limit is higher. Start with one
`Setting` for the global maximum; expect it to become a per-class or per-vehicle number in the
same place the seat counts live.

## 5. The application is a review, and the vehicle is part of what is reviewed

*"we will check the quality of the vehicle. That's why I said for apply, we will review, we will
check everything, and then we will decide."*

This is why the courier form is big and the customer form is a phone number. What the review
covers: identity and guarantor, the documents, **and the vehicle** — its class, its seat count,
its condition, from the `vehicle_photo` already collected. A courier's vehicle determines what
he can be offered, so an unreviewed vehicle claim is a dispatch decision made by the applicant.

## 6. The order code must work on paper

*"they should be able to print if they want, otherwise they can just write the number on
paper."*

`orders.code` already exists with a unique index. What this requires of it:

- **Short enough to write by hand and read back over a phone.** Not a UUID.
- **Latin digits and LTR even in Pashto and Dari** — already the rule in `AFGHAN_UX.md`, and
  already true for phone numbers. A code is useless if it renders in a script the person taking
  it by phone cannot transcribe.
- **Unambiguous when spoken and when handwritten.** Avoid characters that collide: 0/O, 1/I/l,
  5/S, 8/B.
- **Printable, and legible without printing.** Large on the merchant's order card, because the
  fallback is a pen. Printing is a nice-to-have; **writing it down must always work.**

A restaurant with no printer, no tablet charger and a queue at the counter is the normal case,
not the degraded one.

## 7. What is NOT being built yet

- Batching itself — the route ordering, the multi-leg step list, the summed cash checks.
- Per-vehicle batch limits (one global `Setting` first).
- Seat counts sourced per vehicle rather than per class.
- Printing. The code must be writable; a print path comes when a merchant asks for it.

**What IS being built now:** the tier column on orders and trips, its effect on the quote, its
appearance on the cart and on the courier's offer card, the seat axis in eligibility, and the
order code meeting the rules in §6.

## 8. The privacy rule, restated because it now has a mechanism

From correction 19, and unchanged: **in a shared job neither customer sees anything about the
other** — not a name, not a phone, not an address, not their stop. The courier sees every leg;
each customer sees only their own. Choosing the cheaper tier consents to *sharing a courier*, and
to nothing else about the other person.

---

## 9. The premium incentive inverts the day batching ships

Found before it could bite, and it is a business-model bug rather than a code one.

**Today the premium uplift is the platform's, and that is correct** — nothing can be batched, so
a courier on a premium job gives up nothing and is owed nothing extra.

**The day batching ships, that becomes backwards.** A premium job would pay him the same as a
normal one while *forbidding* him to combine it. So couriers would prefer normal work, and
**premium customers — who paid more precisely to be prioritised — would wait the longest.** The
tier would invert its own promise.

**The fix is a number, not a redesign:** share the uplift with the courier at that point, enough
that a premium job is worth at least as much to him as a batched normal run. Decide it when
batching lands, with real batch rates to price against.

**A ride already behaves correctly**, because there the fare is the driver's revenue and we take
a percentage — so a higher premium fare pays him more automatically. Only delivery has the
inversion, because there the courier's fee is a separate number from the customer's total.

## 10. The order code: digits only, and why that is the whole rule

§6 asks for a code that survives a pen, a phone call and Pashto. The implementation is a short
prefix plus **six digits** — and the reason digits-only settles it is worth stating:

**Every collision §6 names is a digit against a letter** — 0/O, 1/I/l, 5/S, 8/B. So an alphabet
with no letters in it cannot contain any of them. No exclusion list to maintain, no judgement
call at the edges.

A spec asserts the alphabet, deliberately, because *"let's use base32, it's shorter"* reads as an
improvement and would reintroduce all four collisions at once.

---

## 11. Seats and per-vehicle ride pricing — Hamma9900's numbers

**Seats, and note the car is capped BELOW its physical capacity.** His words: *"one vehicle can
have four seats but we said three."*

| Vehicle | Passengers |
|---|---|
| car | **3** (physical 4) |
| rishka | **2** |
| motorbike | **1** |
| bicycle / on_foot | not offered rides |

Capping the car at 3 is deliberate — comfort, and it keeps the promise being sold. Record the
physical count separately at application (§5) if it is ever wanted; the **offerable** number is
what dispatch uses.

**Per-vehicle ride pricing — confirmed, and it is why the passenger picks the class.** His
example: the same trip is about **100 AFN by car** and **70–80 by rishka**. So the rate rows in
`pricing_rates` under `ride / customer / <vehicle>` carry genuinely different tariffs, not one
tariff with a multiplier.

**This is what makes the upfront quote honest.** The passenger chooses cheap-and-open or
comfortable-and-closed, sees that class's price, and dispatch then offers only to that class —
so the fare cannot move after they agreed it (correction 13). A family of four cannot select
motorbike, because the seat axis removes it from the picker before the price is shown.

## 12. The courier's declared float — the cash gate that replaces the deposit

Since a courier owes the platform nothing (see `MONEY_AND_SETTLEMENT.md`), the wallet no longer
represents money we hold, so it cannot gate dispatch. **The courier declares his own working
cash instead.**

- He taps a number at the start of a shift — Hamma9900's benchmark is **1,000 AFN**, checked as
  a qualification during the application review rather than held by us.
- **Dispatch never offers a job whose advance exceeds his remaining declared float.**
- **The float DECREMENTS as he accepts and restores on delivery.** Declares 1,000, takes a 500
  job, has 500 to work with until he collects — exactly Hamma9900's two-orders-of-500 example,
  with the platform doing the arithmetic rather than trusting him twice.
- **Self-declared is honest here because lying only costs him**: he would accept work he cannot
  fund and lose it.
- **This is why the restaurant never cooks for a courier who cannot pay** — the case is refused
  at the offer, not discovered at the counter. A courier who arrives unable to pay anyway gets a
  reason code and a strike, because the cost should land on whoever caused it.

**Two numbers, not one.** The **float** is what dispatch reads and it moves all day. **Earnings**
are cumulative and only go up — and that is the number the courier actually wants to see.
