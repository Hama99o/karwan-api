# Money, cash and settlement — Model A in full

> **Status: BINDING, and Hamma9900 calls this the most important part of the platform.**
> *"It's our future. This is the main place where we have to do."* Every other document defers
> to this one on anything about money. Read with `CLAUDE.md` corrections 6 and 13.

---

## 1. The principle: no money passes through us

We never hold customer money. **Cash moves between the three people who are actually present**,
and we only ever collect a commission afterwards, by bank deposit.

That is what makes launching possible with no payment provider, no merchant account and no
banking integration. It is also what makes the wallet and the settlement discipline
load-bearing: **the commission is the entire revenue, and it arrives days later.**

## 2. THE CASH FLOW — the most important thing in this document

Hamma9900 called this the most important part of the platform, and this section is the answer.
Worked in his own numbers: a **300 AFN** meal, a **100 AFN** delivery, a **50 AFN** restaurant
commission, and a **15 AFN** platform margin on the delivery.

```
CUSTOMER  ──── pays 400 in cash ────►  COURIER
                (300 food + 100 delivery)      │
                                               │ earlier paid 315 in cash
                                               ▼
                                          RESTAURANT
                                          keeps 250
                                          owes the platform 65
                                               │
                                               │ walks to a bank, weekly
                                               ▼
                                            PLATFORM
```

| Party | Pays | Receives | Ends with | Owes the platform |
|---|---|---|---|---|
| **Customer** | 400 | the food | — | **never anything** |
| **Courier** | 315 to the restaurant | 400 from the customer | **85, his fee** | **NOTHING** |
| **Restaurant** | 315 received, 250 kept | | 250 | **65** |
| **Platform** | — | 65, in one deposit | **65** | — |

### The three things that make this shape right

**1. ONLY TWO PARTIES EVER DEPOSIT MONEY: restaurants and taxi drivers.**

A **food courier never pays the platform anything.** No wallet debt, no settlement, no walk to a
bank, no chasing two hundred small debtors who each owe a few Afghani and can vanish on a
motorbike. That was Hamma9900's instinct and it is the single biggest simplification in the
model.

**2. The platform's cut from the courier arrives THROUGH the restaurant.**

The courier pays the restaurant **315 for a 300 meal** — the food plus the platform's 15. The
restaurant collects it and adds it to what it deposits. So the restaurant is the **single
collection point for all food revenue, from both sides**, in one weekly payment.

This is the part that needed solving: in a pure cash model the courier physically holds the
money, so the platform cannot take a share of his fee without turning it into a debt. Routing it
through the restaurant keeps the courier debt-free while the platform still earns on both sides.

**3. The customer pays the courier, and never the platform.**

Food plus delivery, one number, one payment, in cash at the door. Both commissions are invisible
to them. *"We will not cut from the customer"* — Hamma9900.

### What each screen must show

- **The courier's step says "pay 315".** One number, one action. He does not need to know what is
  inside it, and the fee he keeps is simply 85 — introduced as the fee rather than as a
  deduction, because *"you owe us 15"* and *"the fee is 85"* feel like different jobs.
- **The restaurant's board says "collect 315 — 300 food, 15 platform"**, so they know why it is
  more than the menu price. Transparency with restaurants is a stated requirement and this is
  where it matters most: an unexplained 15 looks like a mistake or a skim.
- **The customer sees 400**, itemised as food and delivery. Nothing about commission.

### Timing, which is a judgement rather than a rule

The courier's fee starting at 85 instead of 100 is **a config change, not a build** —
`orders.delivery_fee` (what the customer pays) and `orders.courier_fee` (what the courier earns)
are already separate columns, and `pricing_rates` already splits rates by `audience`.

**But do not take that margin while begging for couriers.** Removing the courier's debt bought
three things: no deposit barrier, nobody to chase, and cheap recruiting. Widening the gap is one
number and can be done the day riders are queuing for work — not while each one is recruited in
a conversation somebody travelled for.

## 3. Who pays the platform, and who never does

| | Pays the platform | How |
|---|---|---|
| **Customer** | **never** | pays the courier once, in cash, for everything |
| **Food courier** | **never directly** | the platform's share reaches it via the restaurant |
| **Restaurant / store** | **yes** | its own commission **plus** the courier-side margin, by bank deposit |
| **Taxi driver** | **yes** | commission on each fare, by bank deposit |

**The taxi driver is the one party who genuinely owes money**, and it cannot be avoided: he
collects the whole fare and there is no third party to route a share through. So rides keep the
wallet, the balance and the deposit — which is why that machinery is not deleted.

## 4. Settlement: they come to us, by bank deposit

Not a payout, not a transfer — **they deposit into our account at a bank near them.**

- We hold all the statistics, so the amount owed is never in dispute: *"we will have all
  statistics."*
- Worked example, his: 20 AFN per ride, 5 rides a day = 100 AFN/day; over five days = 500 AFN,
  deposited at the end of the week.
- The bank name and account details are given in the **contract**, so a courier or restaurant
  knows where to go before they ever owe anything.
- **Each deposit is matched by the 4-digit reference code** already on `courier_wallets`. Names
  transliterate badly (Muhammad / Mohammad / Mohammed) and a code survives a bank statement.

### Non-payment: warn, grace, then stop

1. A **warning** when the amount is due.
2. A **grace period** — two or three days, up to a week. A `Setting`, so he can tune it.
3. Then **the account stops.** No new jobs until they deposit.

Stopping is not a punishment, it is the only enforcement that exists: we hold no card and no
balance of theirs. **This must be in the contract**, and both riders and restaurants must know it
before they sign. A courier who discovers the rule when he is stopped has been treated unfairly
by us, whatever the contract says — so the app must warn him as the date approaches, not on the
day.

## 5. When the food comes back — refused at the door, or cancelled after pickup

> **REWRITTEN 2026-09-16.** This section and case **D** in
> `TRUST_AND_REPUTATION.md` were describing **the same rule** from two ends, and
> two descriptions of one rule is how they drift apart. The money is settled
> here; the strikes, the copy and the fraud reasoning are settled there.

A customer refuses the food at the door, or cancels after the courier has
already collected it. **From the money's point of view these are one case**: the
food exists, nobody wants it, and the courier has already paid the restaurant
for it.

**The rule, in Hamma9900's own numbers** (food 300 — restaurant keeps 250,
courier 20, platform 30):

| | |
|---|---|
| The courier takes the food back and the **restaurant pays him his fee in full** | restaurant −20 |
| **The platform reimburses the restaurant** what it paid out, plus the commission it is forfeiting | restaurant +50 |
| **Restaurant ends** | **+30, and keeps a resellable meal** |
| **Courier ends** | **+20 — paid for the work he actually did** |
| **Platform ends** | **−50** |

**The principle that makes it explainable to a restaurant owner in one sentence:
no commission on a cancelled job, for anybody — and the platform reimburses
whatever the restaurant paid out.** Once the courier has marked picked up he is
owed, however far he got. Before pickup, nothing has moved and nothing happens.

**THE PLATFORM NEVER BUYS THE FOOD, and that is what caps the exposure.** The
meal goes back and is resellable, because Afghan restaurants pre-cook
(`TRUST_AND_REPUTATION.md` §C-bis). So on a 3,000 AFN order the platform does
not lose 3,000 — it loses its commission and nothing more. Commission and
courier fee scale together, so the worst case is *"I earned nothing on this
order"*, never *"I lost the price of the meal."*

**The courier is never out of pocket, and that is the change that deleted §6.**
He is refunded by the restaurant on the spot, in cash, for the amount he
advanced plus his fee. He does not carry the loss home and he does not carry it
into next week.

The customer gets a **strike**, repeated strikes get them looked at by a human,
and the threshold is a `Setting` — all in `TRUST_AND_REPUTATION.md` §2 and §D,
which is also where the wording rules live. *"We will talk with restaurant — if
the customer refuses, the rider will come and give you the food and you will
return the money."*

**For a restaurant contract, one sentence:** *"If an order comes back, you pay
the courier, I refund you that plus my commission, and you keep the food."*

## 6. ~~The 20% recovery rule~~ — DELETED, because the case it covers cannot happen

This section described how a courier left out of pocket by a refusing customer
would recover over subsequent jobs, with the platform carrying the shortfall and
his wallet allowed to go negative. It listed three questions that had to be
answered before it could be implemented.

**None of them need answering, because the courier never goes negative from a
refusal.** §5 above settles it: the restaurant refunds him his advance *and* pays
his fee, in cash, when the food comes back. There is no shortfall to recover, so
there is no recovery rule, no special wallet allowance and no new
`wallet_entries` kind.

Hamma9900's original words — *"we should be negative — for example we will pay
20% of what he was earning"* — were about a world in which the courier absorbed
the loss first. That world was replaced by the restaurant-refunds rule, not
amended.

**Recorded as deleted rather than removed silently**, because an open question
that has stopped being a question is worth one paragraph: the next person to
read *"the courier may go negative"* anywhere in this repo should land here and
find out it is no longer true. **A courier's wallet going negative now means one
thing only — unpaid commission on jobs he completed** — and `blocked?` at the
credit floor is the right gate for exactly that.

## 7. Rides: the fare is collected at the END

> **REWRITTEN 2026-09-16.** This section said *"money before the wheels turn"*
> and quoted *"they should take the money direct before they enter."*
> **Hamma9900 has since rejected collect-at-start**, and the reasoning is
> cultural rather than technical.

**In Afghanistan a fare is paid at the end.** Hamma9900's judgement on asking for
it up front: *"human to human will not happen."* A design that fights that loses,
so the driver collects when the journey finishes — the same moment a Kabul taxi
driver collects today.

The fare is still **quoted upfront and frozen** on the trip (correction 13), which
is the part that matters for trust: the passenger agrees a number before getting
in and pays exactly that number at the end. Upfront *pricing* and upfront
*collection* were never the same thing, and only the first one is the product
promise.

A ride has no restaurant, so there is **no advance and nothing to return** — the
wallet check before a ride offer asks only "is this wallet above zero?", not "can
it fund the goods" (correction 7).

### Cancellation mid-ride: the platform pays NOTHING

Decided, and deliberately **unlike** §5. Full reasoning in
`TRUST_AND_REPUTATION.md` §E; the money, in one place:

1. **Driver and passenger settle the distance between themselves, in cash** —
   which is what they would do anyway if a journey ended early.
2. **The platform takes no commission** on that trip.
3. **The passenger gets a strike.**
4. **The platform pays nothing.**

**Why it differs from food, and it is not inconsistency — it is fraud exposure.**
Hamma9900 identified it: *"maybe they cancel it, they tell the customer to cancel,
to keep the commission."* Any compensation the platform pays on a cancellation is
money **two people standing next to each other can agree to extract**, and a ride
has no third party watching. Food is safer because the restaurant is a witness and
the courier must ride back to be paid, so a faked cancellation costs him a wasted
round trip.

## 8. THE EDGE CASE HAMMA9900 HAS NOT SEPARATED, AND IT MATTERS MOST

He described a reassignment rule: *"if it's two kilometres and you didn't come in two hours, we
pass the same delivery to another rider and they will restart it."*

**But that rule means two completely different things depending on one fact: had the first
courier already paid the restaurant?**

| | Before pickup | **After pickup** |
|---|---|---|
| Where is the food? | with the restaurant | **gone, with courier A** |
| Where is the money? | in A's wallet | **paid to the restaurant** |
| Can courier B just take over? | yes — reassign and continue | **no.** B must buy new food |
| Who bears the 1,000 AFN? | nobody, nothing moved | **courier A** |

**After pickup, reassignment is not a reassignment — it is a new order plus a loss.** Courier B
pays the restaurant again for fresh food; the original 1,000 AFN is charged against courier A's
wallet, and **that is precisely what the deposit requirement in §2 exists for.** So the model
holds — but the code must treat the two cases separately, and the timeout job must branch on
`merchant_paid_at`.

Everything downstream follows from that column: whether the customer's order code stays the
same, whether the restaurant is asked to cook again, and whose wallet is debited.

## 9. The reminder system, before any penalty

Before a timeout takes a job away, the platform **contacts the courier** — Hamma9900's
instruction. *"Tell him: if there is any emergency tell us, if there is anything tell us, if the
charge is finished."*

This matters because the honest explanations are ordinary: his phone battery died, he had an
accident, the customer's gate was locked, he got lost. A platform that reassigns silently and
penalises treats a flat battery like theft — and in a market where every courier was recruited
in person, that is how you lose the courier and the three he would have brought.

So the order is: **ask, wait, then reassign.** A reachable courier who says "ten more minutes"
keeps the job. Only silence triggers the timeout. The delay is distance-based (his example: 2 km
in 2 hours) and belongs in `Setting` rows rather than in code.

## 10. What must be true in the code

- **Every amount frozen at the moment it is quoted** (correction 13), with the customer-facing
  total frozen at quote and the courier's earnings at assignment.
- **Every balance change goes through `CourierWallet#record_entry!`** — one locked entry point,
  one ledger row, `balance_after` recorded, and the actor named. No code path may move money
  without leaving a row saying who moved it.
- **The ledger is append-only.** No `updated_at`, and a correction is a new entry, never an edit.
- **Signed, bidirectional balances and amounts stay that way.** No non-negative constraint — §6
  requires negatives, and online payment later inverts who holds the money.
- **`cash_in_hand_limit` is the second exposure control** and is separate from the wallet: the
  wallet protects the goods, this protects cash already collected and not yet deposited.
- **Settlements store expected AND counted, plus the name of the person who counted.**
- **Never sum across currencies.** AFN-only today, which is exactly when the habit is cheap.

## 11. Numerals, since money is where it shows

Per-locale digits: **Eastern Arabic (۰۱۲۳۴۵۶۷۸۹) in Pashto and Dari, Latin in English** — his
instruction, and already built in `i18n/numerals.ts`. The exceptions stay Latin and LTR
everywhere: **phone numbers and order codes**, because both get read aloud and written on paper.
