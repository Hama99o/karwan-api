# Designing Karwan for Afghanistan

Hamma9900's instruction: **it must be easy for Afghans to use.** He is Afghan, building for
Afghans, and this document outranks generic mobile best practice wherever they conflict.

These are not "nice to have". Several of them are the difference between an app that works
and an app that only works for the small minority who resemble a Western user.

---

## 1. Assume the user may not read fluently — this is the dominant constraint

A large share of Afghan adults cannot read fluently, and the share is lower again for women
and in rural areas. **Design for a user who recognises pictures, numbers and places, not
sentences.**

- **Photos of the actual food**, large, on every catalog item. A photo sells and explains
  where a description cannot.
- **Icons with text, never icons alone and never text alone.** An unlabelled icon is a
  guess; a label with no icon is unreadable to some users.
- **Numbers do the heavy lifting.** Price, quantity, minutes, distance. Keep them large.
- **A voice note instead of typing.** See §3 — this is the single highest-value feature in
  the whole app for this market.
- **A tappable phone number on every screen, for every role.** When the interface fails,
  a phone call is the fallback that always works. Never make someone hunt for it.
- **Never explain with a paragraph.** If a screen needs a paragraph, the screen is wrong.

## 2. Use the Solar Hijri (Shamsi) calendar for display

Afghanistan runs on the **Solar Hijri calendar**, not Gregorian. A date rendered as
"15 September 2026" means little to many users; **۱۳۹۵/۰۶/۲۴** is the date they recognise.

- **Store UTC. Render Shamsi.** Never store a localised date.
- Every date a user sees — order history, receipts, settlement dates — renders Shamsi in
  Dari and Pashto, and may render Gregorian in English.
- This is routinely forgotten and then expensive, because it touches every screen showing a
  date. Solve it once in the localisation layer, like currency.

## 3. Typing Pashto or Dari on a phone is hard — so minimise typing

Many people do not have the keyboard installed, or do not type in their own script even when
they read it.

- **Voice note for the delivery address.** Typing "the blue gate near the mosque, second
  floor" in Pashto is the hardest single action in the whole flow. Saying it is trivial. Pin
  on the map + voice note + phone number is a better address than any text field.
- **Search must tolerate Latin transliteration.** People type `kabab`, `kabob`, `کباب` and
  `qabuli` for the same thing. Match all of them, or search returns nothing and the user
  concludes the app is empty.
- **Prefer choosing over typing** everywhere: quantity steppers not number fields, saved
  pins not re-typed addresses, a reason list not a free-text box.
- **One full-name field, not first and last.** Afghan names frequently do not split into
  two parts, and forcing it produces wrong data and a confused user.

## 4. Numerals are locale-dependent

Dari and Pashto commonly use Eastern Arabic numerals — **۰۱۲۳۴۵۶۷۸۹**. Render numerals per
locale in the localisation layer, the same place as currency and dates.

Two things that stay Latin and left-to-right even inside RTL text: **phone numbers** and
**order reference codes**. Mirroring those makes them unusable.

## 5. Build for a cheap phone on an expensive, patchy connection

- **Small images, cached hard.** Never re-download a catalog.
- **Offline map tiles** — the courier in a stairwell still needs the map. Pre-download the
  working city.
- **Every screen has a useful offline state**, not a spinner. Show the last known data with
  a quiet "not updated" marker.
- **Few animations, light app, works at 360dp.** Test on the oldest Android you can find,
  not the newest.
- **Data costs the user real money.** Poll rarely; batch courier location updates.

## 6. Show everything about money before it is owed

Low institutional trust is a market condition, not a flaw to design around with cleverness.
Be unambiguous instead.

- **The price, in full, before confirming.** Food, delivery fee, total. No surprises at the door.
- **The exact cash amount** on the courier's screen and the customer's, plus **whether change
  is needed**. People carry particular notes.
- **A receipt after every order**, retrievable later.
- **The courier's name and photo** before they arrive — for the customer, and especially for
  a woman expecting a stranger at the door.

## 7. Phones are shared

A phone in a household may be used by several people.

- Sessions expire. Do not keep someone logged in forever on a device that isn't theirs.
- **Log out must be easy to find** — not buried three taps deep in a settings screen.
- Never show a full phone number or address on a screen reachable without authentication.

## 8. Language is the first question, not a settings item

- **Ask for the language before anything else**, on first launch, with the choice written in
  each language — پښتو / دری / English — never as flags. Flags are ambiguous and political.
- Default from the device locale, but **always let them change it**, and let them change it
  again from a visible place.
- Remember it per user, not per device.

---

## The test that matters

**Hand the phone to someone who cannot read and see whether they can order food.**

Every decision in this document is downstream of that test. Hamma9900 can run it with real
people in Kabul — and his own family, which is the fastest honest feedback available to this
project. No amount of internal review substitutes for it.
