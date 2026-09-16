# Trust, ratings and reputation

> **Status: BINDING** for what is decided; §5 is explicitly OPEN and is the next design
> conversation. Hamma9900's decisions, 16 Sept 2026. Read with `MONEY_AND_SETTLEMENT.md` §5,
> which owns the strike mechanism this feeds.

---

## 1. Ratings: two thumbs per order, and nothing else

**One thumb up or down on the RESTAURANT, one on the COURIER.** Per order. That is the whole
v1 rating system.

- **Thumbs, not stars.** A star scale asks the user to read it and decide where on it they sit.
  A thumb is one tap and needs no literacy at all — `AFGHAN_UX` §1.
- **Two subjects, because that is the split that acts.** When food arrives cold the customer
  blames the restaurant *and* the courier. Separating those two is the only distinction that
  changes what you do next; everything finer is analysis you cannot act on yet.
- **NOT per dish.** One thumb is one tap; rating each item is three or four. Dish-level data only
  becomes useful once a restaurant has enough volume to compare its own items against each
  other, which is months away. Add it then, not now.
- **Rides get the same**: one thumb on the driver.

**Why this comes before any level system:** there are no ratings in the platform today, so
Hamma9900 cannot see which restaurant sends cold food or which courier arrives rude. He hears
about it from a customer who has already left. **This is operational blindness, not a missing
game.**

## 2. The customer is not rated. What went wrong is COUNTED

**Do not build a customer rating.** A score on a customer is a judgement that does nothing.
Instead the courier reports a **reason**, and reasons accumulate.

| Reason | Why it matters |
|---|---|
| address was wrong | the commonest real failure; Kabul has no reliable street addressing |
| did not answer the phone | the courier is standing in the street, unpaid |
| refused the order | triggers the return-to-restaurant path and a strike |
| the note was fake | see §4 |
| made me wait | the courier's time is his income |

**Half of this already exists.** The courier's job screen has problem buttons — *customer not
answering*, *customer refused*, *restaurant not ready*, *call support* — each recording a reason
and reaching admin. **What is missing is that those reports should accumulate against the
customer** and feed the strike threshold in `MONEY_AND_SETTLEMENT.md` §5.

**This is stronger than a rating because it protects the side that cannot be replaced.** A
courier who is sent to four wrong addresses in a month stops working. And *"four wrong
addresses"* is a conversation Hamma9900 can have; *"2.1 stars"* is not.

## 3. Gamification: couriers and drivers ONLY

**Yes for couriers and drivers. No for customers. No for restaurants.**

**The rule:** gamify where there is a retention problem and no contract. That is the courier and
nobody else.

- **Couriers and drivers** are paid in cash at the door, hold no account with us, and can leave
  tomorrow. **A reputation they built is the only thing they cannot take to a competitor.**
- **The reward is BETTER WORK, not badges.** Priority on offers, access to premium (exclusive)
  orders, a higher declared-float allowance. Those cost nothing and are worth more to a courier
  than any number. A performance bonus — Hamma9900's example was 100 AFN a week — pays for
  itself if it prevents one courier quitting, because replacing him costs a conversation
  somebody has to travel for.
- **Customers: no.** Hungry people do not need gamifying. Nobody orders a second kebab because
  they levelled up. What brings a customer back is food arriving hot, on time, at the quoted
  price — operations, not points. And a customer points scheme is **a discount programme wearing
  a costume**, spending margin on the revenue side rather than on the scarce side.
- **Restaurants: no.** A restaurant wants to know how many orders it got and what it owes.
  That is the Today screen and the console. A badge adds nothing and slightly insults them.

**Build order: ratings → courier and driver levels → nothing else until there are more users
than problems.**

## 4. Counterfeit notes — decided, because the first case should not decide it

**The platform never touches the cash, so it cannot verify it.** The only workable rule: **the
courier checks notes at the point of collection, and a fake note he accepts is his loss.**

That is harsh and it is the honest position — any other rule means the platform absorbs a loss
it cannot audit. **So it belongs in the courier's contract**, stated before he starts, and the
reason should be given rather than the rule alone. A `fake_note` reason code on the customer
(§2) is how a pattern gets spotted; a customer who passes two is not making mistakes.

---

## 5. OPEN — cancellation. The next design conversation

Hamma9900: *"we still have a problem, cancelling order and things — we didn't clear this part."*
He is right, and these are the cases, with what is already known about each.

**A. The rider cancels. NOT a problem — decided.** From Hamma9900's own delivery experience in
France: a rider accepts quickly so nobody else takes it, then sees the distance and cancels.
That is normal behaviour, another rider picks it up, and the platform should not penalise it.
**But it needs a limit** — a rider who cancels half his offers is gaming the queue, and that is
a reason code, not a strike.

**B. The restaurant cancels. THE DAMAGING ONE.** The customer has already committed. The
**sold-out toggle already exists** — endpoint and board control — and prevents most of it: a
restaurant that marks the qabuli palaw gone never takes the order. What is missing is that
**cancellation reasons should be tracked per restaurant**, so a restaurant cancelling a fifth of
its orders is visible before its customers leave.

**C. A restaurant cancels, including while cooking. DECIDED — no consequence, and the message
does the work.** Hamma9900: *"when restaurant cancel it, it's done, nothing will happen — but we
will tell the customer that unfortunately this food is not available, and very very typical so he
did not get angry."*

So: **no financial consequence in v0.** No penalty on the restaurant, no compensation to the
customer. With ten restaurants he knows personally that is the right trade — a penalty regime
costs him relationships he needs more than it saves money he has not lost.

**But the copy is the product, so five rules on it:**

1. **Blame nobody.** "The restaurant cancelled your order" invites anger at the restaurant he
   needs. **"Unfortunately this is not available right now"** is the same fact with no target.
2. **Say the money is safe, first.** Cash-first means nothing was paid — so **"you have not paid
   anything"** removes most of the anger before it forms. This is the single most important line
   and it must not be buried under an apology.
3. **Offer the next step, not just the news.** "Choose something else" or "see other restaurants
   nearby". **A dead end is where a customer uninstalls**; a bad outcome with a way forward is
   just a bad evening.
4. **Keep it to two lines.** A paragraph reads as an excuse, and an excuse invites argument.
5. **It must arrive as a PUSH notification, not only in the app.** A customer waiting for food is
   not staring at the screen. The same plumbing already carries the merchant alert, the arrival
   notice and the applicant's review outcome — this is its fourth use.

**And still track it.** No penalty does not mean no visibility: cancellation reasons per
restaurant, so a restaurant cancelling a fifth of its orders is something Hamma9900 can see and
talk about. Visibility is not a penalty, and the data is already recorded.

**D. The customer cancels AFTER pickup. UNRESOLVED, and the hardest.** The courier has paid the
restaurant with his own cash and is holding food. `MONEY_AND_SETTLEMENT.md` §5 gives him the
right to return it and be refunded — but that is written for a *refusal at the door*, not a
cancellation while he is riding. The cases may want different answers.

**E. A ride cancelled mid-journey. DEFERRED by Hamma9900**, and he has called it critical. The
shape will mirror §5 — a proportion paid, a strike recorded — and it is not v0.

**What must be true whichever way these land:** every cancellation records **who** cancelled,
**when**, and **why**, from a fixed list rather than free text, and lands in the audit trail.
That much is already built and must not be traded away for speed — a cancellation nobody can
attribute is a dispute nobody can settle.
