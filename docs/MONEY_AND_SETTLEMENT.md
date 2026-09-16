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

## 5. When the customer refuses the food

The courier has already paid the restaurant. He is out of pocket and holding food nobody wants.

1. **He has the right to return the food to the restaurant and recover his money.** The
   restaurant is contracted to accept the return and refund him. *"We will talk with restaurant
   — if the customer refuses, the rider will come and give you the food and you will return the
   money."*
2. **The customer gets a strike.** Recorded on their account.
3. **Repeated strikes get them blocked.** A `Setting` for the threshold, and a human looks
   before it happens — the reason matters, and sometimes the customer is right.
4. **The courier is made whole**, partly by us and partly from future work. See §6, which is
   the one part still to settle.

## 6. OPEN — the 20% recovery rule needs one clarification

Hamma9900: *"we should be negative — for example we will pay 20% of what he was earning, they
will recover their money, but we will be in negative. Next delivery he will do, we will pay to
him and they will cover all money."*

The intent is clear: **a courier left out of pocket by a refusing customer is not abandoned.**
He recovers over subsequent jobs, and the platform carries the shortfall in the meantime — so
his wallet may go **negative** and he keeps working.

What is not yet precise enough to implement:

- **20% of what, exactly?** Of his earnings on each following job, applied against the
  shortfall? Or 20% of the loss paid immediately by us?
- **Does the negative wallet still block new jobs?** `blocked?` refuses at the floor today. A
  courier who cannot work cannot recover, so this case must NOT use the normal gate — it needs
  its own allowance.
- **What is the floor?** How negative may a courier go before we stop him, and does a refusal
  loss count differently from unpaid commission?

**Do not implement this by guessing.** The ledger shape supports it already — balances and
amounts are signed and bidirectional, deliberately — so the recovery is a `wallet_entries` kind
and a rule, not a migration.

## 7. Rides: money before the wheels turn

*"There will be a rule for driver — they should take the money direct before they enter."*

A ride has no restaurant, so there is no advance and no goods to return. The fare is agreed
upfront and frozen (correction 13), and the driver collects it. **Cancellation mid-journey is
the hard case** — Hamma9900 has flagged it as critical and deferred it: the shape will mirror
§5, a proportion paid and a strike recorded. Not v0.

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
