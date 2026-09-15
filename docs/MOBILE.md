# Karwan mobile — the stack, and it is Hatiwal's

Read `CLAUDE.md`, then `docs/AFGHAN_UX.md`, then `docs/DESIGN.md`. This file settles the
technology; `DESIGN.md` settles what it looks like. **One app, three role modes.**

---

## Use Hatiwal's stack. Not a similar one — the same versions.

Hamma9900's instruction: *"choose same framework as we have for hatiwal, it should be same."*
Measured from `Personal/Hatiwal/hatiwal-mobile/package.json` today, not from memory:

| | Version | Why it stays |
|---|---|---|
| `expo` | ~54.0.17 | EAS build/submit already works for his Apple and Google accounts |
| `react` / `react-native` | 19.1.0 / 0.81.5 | pin to these; a version skew is a day lost to native builds |
| `expo-router` | ~6.0.23 | file-based routing — the role modes become route groups |
| `@maplibre/maplibre-react-native` | ^11.3.6 | **the** map client; works with our self-hosted tiles |
| `expo-location` | ~19.0.8 | GPS, foreground while a job is active |
| `nativewind` + `tailwindcss` | ^4.1.23 / ^3.4.17 | logical spacing utilities, which RTL needs |
| `zustand` | ^5.0.4 | client state |
| `@tanstack/react-query` | ^5.75.2 | server state, caching, and the offline "last known" story |
| `i18next` + `react-i18next` | ^25.0.1 / ^16.0.0 | ps / fa / en with RTL |
| `react-native-reanimated` | ~4.1.1 | the little motion we allow |
| `jest` + Maestro | ^29.7.0 + `qa/` | Hatiwal's QA rig shape — copy it, it is proven |
| `typescript` | ~5.9.2 | strict |

**The benefit is not familiarity, it is debt already paid.** Hatiwal has ground through EAS
credentials, Android build config, MapLibre lifecycle bugs, i18n plural keys that render as raw
strings, and 34 physical-to-logical spacing fixes. Same versions means those fixes transfer.

### One thing NOT to copy

`hatiwal-mobile` carries **both** `@maplibre/maplibre-react-native` and `react-native-maps`.
Its own map README has a section titled *"The three clients currently disagree, and two of them
are wrong"* — that is this. **Karwan installs MapLibre only.** One map client, no exceptions.

---

## Route line — start point, end point, and the path between

Hamma9900 asked whether it shows the start and end line. Yes, and this is what OSRM buys us
beyond a number: a `/route` response carries **distance, duration and the route geometry**.

- Draw the geometry as a MapLibre `ShapeSource` + `LineLayer`. One line, the accent colour,
  under the markers not over them.
- **Two distinct markers, not two pins of the same shape.** Start and end must be
  distinguishable at a glance by a courier moving in sunlight — different shape, not only
  different colour, because colour alone fails for the colour-blind and in glare.
- Fit the camera to the line's bounds with padding on first render, then let the user move it.
  Never snap the camera back while they are panning.
- **The line is drawn from the server's geometry, never from the courier's GPS trail.** A trail
  of pings is where the courier *has been*; the line is where the job *goes*.
- When routing is unreachable, draw a straight dashed line between the two points and label it
  as approximate. Degrade, never blank.

---

## Three role modes, one component library

`DESIGN.md` is binding on this; the mechanics here. Hamma9900 again: *"the design should
change for rider, restaurant and client."* It changes in **layout, density and colour only.**

- **Route groups, one per role** — `app/(customer)/`, `app/(merchant)/`, `app/(courier)/`,
  mirroring the API's role namespaces. Customer gets tabs; merchant and courier get one screen
  each and no tab bar.
- **One `components/ui/` primitive library** shared by all three. A role never gets its own
  Button. If a role needs a bigger button, that is a size token, not a component.
- **Theme tokens per role**, one file — the same semantic names resolving to different values.
  The courier's primary action is enormous and near-black on amber for sunlight; the merchant's
  surface is dense and neutral so order states carry the colour; the customer's is warm and
  roomy. Same token names, so a component never branches on role.
- **The map style also changes per role** — and that is free, because a style is a JSON file
  served from the shared map. The courier's map is high-contrast and stripped of anything that
  is not a road or the destination; the customer's can carry more landmarks. **One tileset,
  several styles** — never a second tileset.

## Non-negotiables from AFGHAN_UX.md

RTL-first (build in Pashto or Dari, check English). Logical properties only. Photos over text.
Icons always with labels. The address is a map pin plus a held-to-record voice note, never
typed. 48dp targets, 64dp for the courier's primary action. Every screen has an offline state
showing last-known data with a quiet "not updated" mark. Test at 360dp on the oldest real
Android available, never only an emulator.
