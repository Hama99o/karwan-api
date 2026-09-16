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

**C-bis. Afghan restaurants PRE-COOK, which largely dissolves C.** Hamma9900's local knowledge,
and it changes the reasoning rather than the conclusion: *"in Afghanistan the restaurant family
almost cook everything — fried chicken, kabuli palaw — they are almost cooked. Karahi maybe it's
not cooked."*

So a cancellation usually costs the restaurant **nothing** — the dish goes to the next customer.
The wasted-meal problem barely exists, and neither a compensation scheme nor a
cancel-before-cooking window is needed. *"Unfortunately it has been cancelled"* is the whole
answer. Karahi and other made-to-order dishes are the minority exception.

**And the more valuable consequence, which is a product advantage rather than a risk:
pre-cooked food means prep time is near zero for most dishes.** Western food apps quote a kitchen
that starts when the order lands; Karwan's quote is mostly the ride.

`catalog_items.prep_time_minutes` already exists per item, falling back to the merchant's
default — so karahi can be 20 minutes and kabuli palaw 2, and the quote computes the right
figure per basket. **Set these honestly and a 10-minute ETA is something customers talk about.
Set one lazy number per restaurant and the advantage is thrown away**, promising 20 minutes on
food already in the pot. Worth saying to every merchant at onboarding.

**D. The customer cancels AFTER pickup. DECIDED.** Hamma9900's design, in his numbers: food
300, restaurant keeps 250, courier 20, platform 30.

> **THE MONEY LIVES IN `MONEY_AND_SETTLEMENT.md` §5, which is the same rule as
> this one.** A refusal at the door and a cancellation after pickup were written
> up separately and are identical from the money's point of view: the food
> exists, nobody wants it, the courier has already paid. The table below is kept
> here because the *strikes and the copy* are this document's job — but if the
> two ever disagree, **§5 is the money and this is not.**

| | |
|---|---|
| Courier returns the food; **restaurant pays him his 20 in full** | restaurant −20 |
| **Platform pays the restaurant 50** — their 20 back, plus the 30 commission forfeited | restaurant +50 |
| **Restaurant ends** | **+30, and keeps a resellable meal** |
| **Courier ends** | **+20 — paid for the work he did** |
| **Platform ends** | **−50** |

**The principle, which is what makes it explainable: no commission on a cancelled job, for
anybody — and the platform reimburses whatever the restaurant paid out.** Once the courier has
marked picked up he is owed, however far he got. Before pickup, nothing happens.

**For a restaurant contract, one sentence:** *"If an order is cancelled after pickup, you pay the
courier, I refund you that plus my commission, and you keep the food."*

**THE PLATFORM NEVER BUYS THE FOOD, and that is what caps the exposure.** The meal goes back and
is resellable because Afghan restaurants pre-cook (§C-bis). So on a 3,000 AFN order the platform
does not lose 3,000 — it loses its commission on it and nothing more. Commission and courier fee
scale together, so **the worst case is "I earned nothing on this order", never "I lost the price
of the meal."** On a cheap order with a long ride the fee can exceed the commission; that is rare,
a few tens of Afghani, and not worth a rule.

**E. A ride cancelled after it started. DECIDED, and differently — the platform pays NOTHING.**

> Settled in money terms in `MONEY_AND_SETTLEMENT.md` §7, which was rewritten to
> match this: it used to say the driver collects the fare *before* the ride
> starts, which is the thing rejected below.

Collect-at-start was considered and **rejected on cultural grounds**: in Afghanistan a fare is
paid at the end, and Hamma9900's judgement is that paying up front "human to human will not
happen". Culture beats design.

So:

1. **Driver and passenger settle the distance between themselves**, in cash — which is what a
   Kabul taxi driver and passenger would do anyway if a journey ended early.
2. **The platform takes no commission** on that trip.
3. **The passenger gets a strike.**
4. **The platform pays nothing.**

**THE REASON IT DIFFERS FROM FOOD IS FRAUD, and Hamma9900 identified it:** *"maybe they cancel
it, they tell the customer to cancel, to keep the commission."* **Any compensation the platform
pays on a cancellation is money two people standing next to each other can agree to extract** —
and a ride has **no third party watching**. Food is safer because the restaurant is a witness and
the courier must ride back to be paid, so a faked cancellation costs him a wasted round trip.

**The leak that remains cannot be fixed by rules:** a driver saying *"cancel in the app and pay
me directly, we both save."* Two defences, and only one is buildable. **Detection** — an
unusually high cancellation rate for one driver, or the same driver-passenger pair cancelling
repeatedly, both visible in data already collected. And the real one: **be worth more than the
commission.** A driver receiving ten rides a day will not risk that flow to save 12.5% on one
fare. **Off-app leakage is a symptom of too little work being sent, not of poor discipline.**

**What must be true whichever way these land:** every cancellation records **who** cancelled,
**when**, and **why**, from a fixed list rather than free text, and lands in the audit trail.
That much is already built and must not be traded away for speed — a cancellation nobody can
attribute is a dispute nobody can settle.
