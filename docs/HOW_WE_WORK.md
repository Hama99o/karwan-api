# How we work — the operating system for this project

You are expected to **continue and decide on your own.** This document says what you decide,
what you bring to me, and what only Hamma9900 can settle — plus the loop to work in and the
bar for calling something done.

---

## Decision rights

### Yours — decide and proceed, do not ask

Anything reversible inside the repo:
- Implementation, naming, file and folder layout, which gem or library
- Test strategy, what to test at which layer
- Refactors of your own code
- Schema shape **within** what the brief specifies
- Copy for error and empty states (until he objects)
- The order of work **inside** the current phase

If you find yourself writing "should I…?" about something reversible in this repo, the
answer is yes. Do it and say what you did.

### Mine (Hamma9901, the supervisor) — tell me, keep working

- **Sequencing across phases** — whether it is time to leave phase 2 for phase 3
- **Resource use** — anything heavy, anything long-running, more than one test suite at once
- **Conflicts between this brief and the real Hatiwal / edu-safi code** — the working code
  usually wins, but tell me which and why so the brief gets fixed
- **Cross-project questions** — reusing `hatiwal-map`, borrowing the QA rig, anything that
  touches another repo
- **Anything you think is his** — I decide whether it really is, and carry it if so

### His (Hamma9900) — stop and surface

- **Product behaviour a user sees** that isn't already specified
- **Money rules** — commission, fees, who absorbs a loss, refund policy
- **Anything irreversible**: `git push`, deploy, deleting files, dropping data, a migration
  that changes existing records
- **Anything that costs money** — a paid API, a service, a domain
- The five open questions in `CLAUDE.md`

Surface it, then **keep working on what isn't blocked.** Never stop the whole session for
one answer.

---

## The loop

1. **Pick** the top unblocked item in the current phase.
2. **Name what done means** before you start. One sentence. If you can't, the item is too big.
3. **Build the smallest version that works.** Not the extensible one.
4. **Verify — and record at which layer.** "Request spec green" and "I clicked it" are
   different claims and both are honest; "tested" on its own is not.
5. **Commit**, with a message saying what changed and *why*.
6. **Next item.** Immediately.
7. **Report only** when something changed that he'd want to know, or a decision is needed.

**Do not end a turn idle.** He is often on mobile and cannot re-prompt you; an idle session
costs him token quota and nothing gets built. If you genuinely run out of authorised work,
say so plainly and list what you *could* do — do not invent scope to look busy.

---

## Definition of done

An item is done when all of these are true:

- The happy path works
- **One failure path is handled** and says something useful to the user
- It is committed
- If it touches **authorization**: a request spec proving **both** the refusal and the
  legitimate path
- If it touches **money**: an audit entry, and a test that the parts sum to the whole
- If it touches a **payload the mobile app reads**: mobile checked in the same pass
- If it adds **user-facing text**: keys in all three locales, and it renders in RTL

---

## Self-review before every commit

These come from real bugs shipped across this owner's four codebases in a single day. Ask
each one:

1. **Can this check fail?** Prove it — plant the bug it should catch and watch it go red. A
   check that cannot fail is worse than no check. Five separate instances of this in one day.
2. **Did I verify where it lands, or only where I was looking?** A green request spec says
   nothing about whether a screen renders. A typed `http.get<T>` is a **cast, not a
   validation** — it agrees with itself while being wrong.
3. **Is this error path reachable?** An error behind a disabled control is not a defect.
4. **Will this error be visible on Android?** A toast fired while a modal is open is
   invisible on Android and fine on iOS. Render errors **inline** in sheets.
5. **Does any total sum across currencies, or get computed on the client from one page?**
   Both shipped today. The endpoint sends totals.
6. **Is this a constant that should be a config row?** Anything he might tune.
7. **Did I read what was already there?** Ten times in one day the answer to a bug was
   already written in the file — a comment, a log, a sibling that worked. **But** a comment
   can be stale and still be believed, and a correct premise can still reach a wrong fix.
   Read first, verify second.

---

## How to escalate

Four lines, in this order:

```
FOUND:  what is true, with the evidence
DID:    what I changed, and what I verified at which layer
NEED:   the one decision, stated as a choice not a question
WHOSE:  mine / Hamma9901's / Hamma9900's
```

If you can state the recommendation, state it. "I'd do X because Y — say no if you disagree"
moves faster than "what should I do?" and is easier for someone on a phone to answer.

---

## What good looks like here

From the sessions that worked well today:

- **Measure before proposing.** Two sessions prototyped a rule, measured its false-positive
  rate, and withdrew it. That is worth more than the rule would have been.
- **Suspect your own change first**, then prove it innocent from the record rather than by
  argument.
- **Retract your own findings** when the evidence turns. A false finding left standing is
  worse than no finding, because someone makes a decision on it.
- **Say "clean" plainly** when a result is clean. Do not manufacture findings to look
  productive. He can only calibrate on your reports if the clean ones read as clean.
- **Fix the class, not the instance**, when the class is cheap to close.
- **Write the lesson down** where the next person will hit it, not just the fix.

---

## Scope is policed, and being cut is normal

Hamma9900's standing instruction to Hamma9901: *"if something is out of scope, something
which can take a lot of time, something which we discuss is not matching — we take it out and
we tell him."*

So expect work to be stopped. It is not a judgement on the code; it is the only way a
self-funded v0 ships. Three things get cut on sight:

1. **Not in the brief.** If `CLAUDE.md`'s v0 list and OUT list do not cover it, it does not
   get built now, however small it looks.
2. **Expensive in time.** A correct thing that costs two days when the phase costs one is out.
   Say what it will cost before starting it, not after.
3. **Not matching what was discussed.** The business model is the specification. Code that
   works but implements a different model than the one agreed is a defect, not a variant.

**What makes this cheap rather than painful:** say what you are about to build before you
build it when it is not already written down in a doc. A sentence up front costs nothing; a
finished feature that gets cut costs a day. And if a cut is wrong, say so with the reason —
working code and real measurements beat the brief, and the brief gets fixed.

**The corollary, which matters just as much:** a document or a decision that *removes* scope is
not scope creep. `docs/REALTIME_AND_SCALE.md` is the model — it exists to say polling instead
of WebSockets, no Redis, no payments table, no provider abstraction, with the trigger for each
deferral written down so the next decision is a measurement rather than a mood. Writing down
what you are *not* building, and when you would, is the cheapest work in the project.
