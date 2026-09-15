# Requirements log — what Hamma9900 has actually asked for

Every requirement the owner has stated directly, dated, in his words plus what it
means for the code. **Nothing here is inferred.** When an item is built, it gets a
commit reference — not a tick, a reference, so the claim is checkable.

The point of this file is that requirements arrived as chat messages mid-task and
would otherwise live only in a session that will be summarised away.

---

## 2026-09-15

### R1 — Registration is not one flow. Riders and restaurants are nothing like customers
> "remember regestration for resurant and rider is very defrent than cline
> client can be simple but not rider and resutrant"

**Customer:** phone + OTP + name. Nothing more. Every extra field is a customer lost.

**Rider:** identity (full name, father's name, tazkira number), vehicle type and
plate, a **guarantor** (name, phone, relation — the real trust mechanism in Kabul,
not a credit check), work area, documents, and an explicit **human approval** with
a name attached. A rider advances our restaurants' food out of their own pocket
and carries our cash.

**Restaurant:** the owner as a person separate from the business (name, phone,
tazkira), licence number, a **contact person who actually answers during a rush**
(often not the owner), documents, and the same explicit approval.

None of it can be collected later. An unverified rider who disappears with a
float is exactly the loss this data exists to prevent.

Built: `20260915120900_add_onboarding_to_riders_and_restaurants` — schema.
Still open: document attachments, the approval endpoints, the admin screens.

### R2 — A good login system
> "and we should good login system"

Phone + OTP, and *good* means the parts people skip:
- OTP codes bcrypt-digested, looked up by phone, never stored in the clear
- Short TTL (5 min) and a **max attempt count** — 6 digits is 10^6 guesses, so
  the attempt counter is the actual protection, not the digest
- **Send throttling** per phone, so the endpoint is not an SMS bill or a way to
  harass a number — NOT YET BUILT, see docs/NOTES.md
- Session tokens 256-bit random, HMAC-SHA256 digested (deterministic, therefore
  indexable; bcrypt cannot be looked up by digest at all)
- Sessions listable and individually revocable; rotating `secret_key_base`
  invalidates every one
- A user with no password column at all, so there is nothing to phish or reuse

### R3 — The best search and category system for food
> "we should have best search system for food best category etc"

Two different things, and they were being conflated:
- `menu_categories` is a **restaurant's own menu structure** ("Starters", "Kebab",
  "Drinks"), entered by the restaurant in its own language.
- **Cuisines** are a **global, seeded taxonomy** ("Kabab", "Pizza", "Burger",
  "Afghan", "Fast food") used to browse and filter across restaurants. This is
  what "best category" means and it did not exist in the first schema pass.

Search must hit **restaurant names and dish names together** — people search
"mantu", which is a dish, not a restaurant — be **multi-word** (each word narrows,
each word can match any field, per the house rule in hatiwal's backend prompt),
and be **typo- and transliteration-tolerant**, because "kabab / kebab / kabob"
are the same food and Pashto/Dari transliterations vary per person.

Built: `20260915121000_add_cuisines_and_search`.

### R4 — Administrate for the admin surface
> "make sure we have well system admistre gem can help to go admin part its
> important"

Settles an open question. `hatiwal-api` already runs Administrate **inside the API
repo** (`app/dashboards/`, `app/controllers/admin/`), which contradicted our brief's
separate `dastarkhwan-admin` repo. The owner's call is Administrate, and putting it
here is also the smaller v0: one repo, one deploy, no second frontend.

### R5 — Test everything, at every layer
> "rspect test evrething and unit test also and later we will do end to end and
> qa also note these thing"
> "we test each method each endpoint eeach policy each serilizer each service in
> backend do not forget this"

See `docs/TESTING.md`. E2E and QA are explicitly **later**, not never.

### R6 — Seeds, and write things down
> "add well seeds etc all with time and put info in claude or note some md file
> for problem its impoartant"
> "add these thing in your md files so you do not forget"

`db/seeds.rb` must produce a world you can actually place an order in.
Problems and lessons go in `docs/NOTES.md`; requirements go here.

### R7 — Push the work, keep pushing it
> "do git init and add git ingore etc" / "and push also" / "with time"

`github.com/Hama99o/dastarkhwan-api`, pushed as work lands rather than in one
lump at the end. The box hard-rebooted this morning and killed seven sessions.
