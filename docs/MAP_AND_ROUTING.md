# The map and routing — brief for the map session

You are extending a **live, working** service. Read `CLAUDE.md` and
`docs/REALTIME_AND_SCALE.md` §5 first. Nothing here is a greenfield build.

---

## What already exists, verified by reading the repo and its runbook

`~/Apps/Personal/Hatiwal/hatiwal-map` — a tile build-and-serve project, live at
**`https://map.hatiwal.com`** since 2026-08-31.

| Piece | What it is |
|---|---|
| Source | `afghanistan-latest.osm.pbf` from Geofabrik |
| Tiles | one 132 MB `.pmtiles`, zoom 0–14, 163,125 tiles |
| `hatiwal_map_tiles` | `go-pmtiles serve` on :8080, read-only, `kamal` network |
| `hatiwal_map_web` | nginx front door — static styles + glyphs, proxies tiles; registered with `kamal-proxy` for the hostname |
| Styles | `build-styles.mjs` + `styles/`, **labels in Pashto and Dari already done** |
| Runbook | `deploy/RUNBOOK.md` and a 16 KB `README.md` — read both, they record bugs already paid for |

**No tile-server process and no database** — a single file read with HTTP range
requests. That is why it costs nothing to run, and that property is not to be
given up.

## What does NOT exist

- **No routing engine IN THE MAP SERVICE.** README §138 is explicit: Hatiwal hands
  navigation off to the phone's own maps app by deep link (`maps://app?daddr=` on
  iOS, a Google Maps link on Android). `map.hatiwal.com` serves tiles, styles and
  glyphs and nothing else.

  > **CORRECTED 2026-09-19 — this line used to end "There is no `/route` endpoint
  > anywhere", and the word *anywhere* outgrew its scope.** It was a statement
  > about the MAP SERVICE, it was true when written, and it is still true of the
  > map service. But `karwan-api` has since grown **`GET /api/v1/route`**, so read
  > globally the sentence became false — and it was read globally. The mobile
  > repo's `services/routing.ts` cites it, having verified a 404 against the map
  > host, and builds `${MAP_URL}/route/v1/driving/…` to this day.
  >
  > **Routing goes through this API, and that is not a preference — it is the
  > only arrangement that can work.** `config/deploy.yml` sets
  > `OSRM_BASE_URL: http://karwan_api-osrm:5000`, a container name that resolves
  > **only inside the Kamal network**. OSRM is deliberately not published to the
  > internet, so a handset cannot reach it directly however the URL is spelled.
  > The extra hop is what makes the router private, and it is also what lets one
  > cached answer serve two phones asking the same question — correction 6's
  > cheapest-at-100-orders-a-day test.
  >
  > A doc sentence scoped to one component and read as a fact about the whole
  > system is its own failure shape. Say which thing does not have it.
- **No geocoding service.** No Nominatim. Hatiwal's search is its own.
- **No offline tile packaging.**

---

## What Karwan needs, in priority order

### 1. OSRM — real road distance and duration. This is the only hard requirement.

**Why it is not optional:** a ride fare is `base + (per_km × distance) +
(per_minute × duration)`. Today `Geo::Distance` uses straight-line distance
divided by an average-speed setting. **Straight-line distance under-measures real
road distance, and in a river-split, one-way-street city like Kabul the gap is
large and not constant.** That is not an ETA being slightly off — it is money,
undercharged on every single ride, on the demand type whose whole purpose is to
fill the couriers' idle hours. A delivery fee has the same problem with a smaller
blast radius.

**Shape:** a third container beside the existing two, same `.pbf` extract,
`osrm-routed` behind the same nginx, exposed as a route on the same hostname.
Car profile for v0 — motorbikes dominate Kabul delivery and will follow car
routing closely enough at this scale; do not build a bike profile yet.

**Non-negotiable constraint: ADDITIVE ONLY.** Hatiwal deploys to production and
starts its campaign before Karwan is announced. You must not change the tile
container, the style build, the nginx tile path, or anything Hatiwal's clients
call. A new upstream and a new location block, nothing else touched. If you
cannot add it without editing an existing path, stop and tell Hamma9901.

**Do the work locally and DO NOT DEPLOY.** Build the OSRM data locally, run it,
measure it, and write the deploy steps into the runbook. Pushing anything to that
VPS while Hatiwal is launching is Hamma9900's decision, not ours. Report what it
will cost in RAM and disk on that VPS before he is asked to approve it — the
`osrm-extract` step is memory-hungry even when `osrm-routed` afterwards is not.

### 2. Offline tiles for the courier app

`REALTIME_AND_SCALE.md` calls this a **v0 requirement for Karwan**, unlike
Hatiwal: a courier in a Kabul side street on a cheap phone cannot be shown a
blank map. The tileset is one file that already supports range requests, so this
is a packaging and cache question, not a new service. Scope it, cost it in
megabytes on the device, and propose — build it after OSRM.

### 3. Geocoding — probably NOT needed. Confirm before building anything.

Karwan already has a `TrigramSearchable` concern and searches merchants and
catalog items in Postgres, and `AFGHAN_UX.md` requires that search match
`kabab`/`kabob`/`qabuli`/`کباب` — which is a trigram-and-transliteration problem,
not a geocoding one. Customers give an address as **a map pin plus a voice note**,
never as typed text, so there is nothing to geocode. **Do not stand up Nominatim
unless you can name the screen that needs it.** Its import is the single most
expensive thing in this stack and it would be run for nothing.

---

## Rules

- **Zero marginal cost per order.** See `CLAUDE.md` correction 6. Self-hosted,
  no metered API on any path an order touches. State the monthly cost of anything
  you propose.
- **One shared service, two apps.** Extend `hatiwal-map`; do not fork it. A fork
  means two tilesets, two deploys and two sets of the bugs its README already
  records as paid for.
- **Measure, do not assume.** Its README has a section titled "Three bugs found
  here that `curl` reported as fine". Verify at the layer the client uses, and say
  which layer you verified at.
- **The straight-line fallback stays.** When OSRM is unreachable, pricing must
  still return a quote rather than fail an order. Keep `Geo::Distance` as the
  fallback and make the source of a distance explicit on the quote, so a fare can
  be explained later.

---

## 4. ZOOM — a conflict between the live tileset and what Karwan needs

**The live tileset is zoom 0–14.** That was the correct choice for Hatiwal, whose README
states plainly that its map is *a search surface, not a navigation map*. Karwan's is the
opposite: a customer drops a pin on their own gate and a courier has to find it.

**Zoom 14 is roughly neighbourhood level.** MapLibre will happily *overzoom* — it scales the
z14 tile when the camera goes past it — so the map does not break, and road layout stays
visible. But **no detail exists beyond z14**: geometry stays coarse, and building footprints
and small alleys are simply not in the data. For dropping a precise pin, overzoom is blurry
rather than broken; for finding a specific gate in a Kabul side street it is not enough.

**The fix, and it is cheap because v0 is one neighbourhood:** keep z0–14 for the whole country
as it is, and add **z15–17 for a Kabul bounding box only.** High zooms are where tile count
explodes, so a country-wide z17 build is out of the question — but a single-city box is small.
Measure it and report the megabytes before building the full thing.

**This is additive in the best way:** a second, higher-zoom tileset for Kabul, or an extended
build of the same one, leaves Hatiwal's z0–14 behaviour byte-identical if you do it as a
separate file. Confirm which shape is cheaper to serve before choosing.

**Verify overzoom behaviour at the layer the client uses,** not with `curl`. A 200 on a z17
tile request proves nothing about what renders on an Android phone, and this repo's README
has a section about exactly that mistake.

## 5. GPS — separate from the map, and mostly a mobile concern

GPS is the device's own satellite fix. It does not depend on the tile server, the routing
engine or the network, and it works in Kabul exactly as anywhere else. What actually matters:

- **Foreground only, while a job is active.** Already the backend's rule —
  `CourierProfile::STALE_AFTER` is 5 minutes and dispatch refuses a stale fix. Continuous
  background tracking drains a cheap phone's battery, and a courier whose phone dies mid-job
  is worse than one who is not tracked.
- **Accuracy on a cheap phone between buildings is 20–50 m, not 5 m.** This is why the design
  never trusts the pin alone: pin **plus** a landmark voice note **plus** a tappable phone
  number. Do not try to engineer the accuracy problem away — it is already designed around.
- **Android permissions are where this breaks, not the satellite.** Foreground location, the
  "while using the app" prompt, and the OEM battery optimisers on cheap Android phones that
  kill background work. Test on the oldest real Android device available, not an emulator.
- **A fix is never a substitute for a route.** Courier position comes from GPS; distance and
  duration for money come from OSRM. Never compute a fare from a chain of GPS pings.
