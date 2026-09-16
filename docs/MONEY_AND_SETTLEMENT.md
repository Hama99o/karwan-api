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

## 2. The normal delivery, in Hamma9900's own example

```
  order = 1,000 AFN of food      customer pays 1,100 AFN
        ↓                                ↑
  COURIER must already hold 1,000 AFN in his wallet
        ↓ pays the restaurant in cash
  RESTAURANT hands over the food
        ↓ courier delivers
  COURIER keeps the delivery fee, and now OWES us commission
        ↓ end of week
  COURIER goes to a bank and deposits what he owes
```

**The courier must have the money before he can take the job.** A 1,000 AFN order is only
offered to a courier whose wallet covers 1,000 AFN. This is `CourierWallet#can_fund?` and it is
**intended, not incidental** — the wallet is the security against a courier taking the food and
disappearing. Hamma9900 has confirmed this directly.

## 3. Who pays us, and who never does

| | Pays us |
|---|---|
| **Customer** | **never.** They pay the courier, once, for everything |
| **Courier / driver** | yes — commission on each job |
| **Restaurant / store** | yes — commission on each order |

*"We will cut from restaurant also, we will cut from rider and driver also, but we will not cut
from customer."*

The customer sees one number and pays it in cash. Both the merchant's commission and the
courier's commission are invisible to them.

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
