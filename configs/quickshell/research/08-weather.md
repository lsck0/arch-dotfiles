# Comprehensive weather widget — research

Scope: replacing/extending `configs/quickshell/plugins/bar/widgets/Weather.qml`
(currently 73 lines: `curl wttr.in/?format=%C|%t` on a 30-minute `Timer`, a
Nerd Font glyph, a plain tooltip) with a hover panel showing today's temp,
feels-like, sky condition, humidity, and a 3-day forecast — using "the
current location but NOT REVEAL IT" per the owner's spec. Read-only
research; no files other than this one touched. Local checks were run on
this machine (`pacman -Q geoclue`, `/etc/geoclue/geoclue.conf`,
`man 5 geoclue`, `busctl`, `systemctl status geoclue`) and are reported as
findings, not assumptions.

---

## RECOMMENDATION

**Provider: Open-Meteo** (`api.open-meteo.com`), not wttr.in.

- No API key, generous free tier, HTTPS, structured JSON with `current`/
  `daily`/`hourly` blocks in one request — no `jq` munging of a
  human-formatted string needed.
- Every actively-maintained Quickshell shell surveyed here (§4) that does a
  *real* forecast, not a one-line current-conditions string, already uses
  it: **caelestia-dots/shell** (`services/Weather.qml`) and
  **AvengeMedia/DankMaterialShell** (`quickshell/Services/WeatherService.qml`)
  both call `api.open-meteo.com/v1/forecast` with essentially the same
  `current=…&daily=…&hourly=…` params — read directly from their QML
  source, not a guess (§4 has exact excerpts).
- Takes `latitude`/`longitude` only — no city name, no IP lookup, no
  account. That's the biggest lever for reading (b) ("don't leak location
  to the provider"): Open-Meteo learns only the two numbers you send it,
  precision fully under your control.
- wttr.in remains a fine **fallback** (§1) — keep `iconFor()`/the existing
  `Process`+`curl` plumbing as the degraded path, since it needs no
  coordinates at all when queried bare.

**Location strategy: layered, resolved locally, coordinates rounded before
any network call.** Precedence, highest first:

1. **Manual override** — a coordinate pair (already rounded) set once via
   a new `toggles/toggle-weather-location.sh`, per this repo's toggle
   conventions. Always wins if present — this is what "current location"
   means when the owner is somewhere a network-based source gets wrong
   (traveling, tethered, etc.).
2. **GeoClue2** (`org.freedesktop.GeoClue2` over D-Bus, `CITY`
   accuracy) when no override is set. WiFi-based — the fix for §3: it's
   **correct regardless of whether Tor/WireGuard/ProtonVPN is up**, unlike
   IP geolocation. Confirmed installed on this machine (`geoclue 2.8.2-1`;
   service `activatable`, currently `inactive (dead)` until requested —
   normal for an on-demand D-Bus service).
3. **Timezone-derived coarse fallback** (`timedatectl show -p Timezone`)
   when GeoClue is unavailable and no override is set — zero network calls,
   a rough per-timezone centroid.
4. **IP geolocation (current wttr.in behavior), demoted to last resort** —
   used only when everything above fails, since it's the one option wrong
   exactly when a tunnel this repo actively toggles is up (§3).

Round whatever coordinate is used to **2 decimal places (~1.1 km)** before
it ever appears in a URL, log line, or cache file (§2 precision table) —
satisfies reading (b) even when GeoClue/override hand back full precision.

**Poll interval: keep the existing 30 minutes**, but add a disk cache
(`FileView`, `~/.cache/quickshell/weather.json`) written after each
successful fetch and read on startup, so a restart shows last-known data
immediately and "full offline mode" (§4) has something to show. Location
re-resolution (GeoClue/timezone/tunnel-state check) can piggyback on the
same cycle — GeoClue calls are cheap and local.

**Display: never render a place name, coordinates, timezone-derived label,
or sunrise/sunset clock time anywhere in the widget or panel** (§2a). Show
only: glyph, temp, feels-like, sky text, humidity %, and a 3-day row of
(short day name, hi/lo, icon). No "Berlin", no "CET", no map pin icon.

---

## 1. Weather data sources

### Open-Meteo (recommended primary)

No key. Free for non-commercial use, HTTPS only. Takes `latitude`/
`longitude` as plain query params — never a city name unless you explicitly
call their separate geocoding endpoint.

**Exact query** for current conditions + 3-day daily forecast including
humidity, min/max temp, and weathercode (adapted from the parameter set
actually used by caelestia-dots/shell and DankMaterialShell, trimmed to
`forecast_days=3` since the spec asks for 3 days, not 7):

```
https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,is_day,precipitation,cloud_cover,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,surface_pressure&hourly=temperature_2m,relative_humidity_2m,precipitation,precipitation_probability,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,uv_index_max&timezone=auto&forecast_days=3&forecast_hours=24

(Superseded the shorter query below after the SPEC was expanded on
2026-09-01 — see §6. This exact URL was executed against the live API with
dummy coordinates: HTTP 200, every requested field present.)
```

Response shape (abridged, real field names):

```json
{
  "latitude": 52.5,
  "longitude": 13.4,
  "timezone": "Europe/Berlin",
  "current": {
    "time": "2026-09-01T14:00",
    "temperature_2m": 21.3,
    "relative_humidity_2m": 58,
    "apparent_temperature": 20.7,
    "weather_code": 3,
    "is_day": 1
  },
  "daily": {
    "time": ["2026-09-01", "2026-09-02", "2026-09-03"],
    "weather_code": [3, 61, 1],
    "temperature_2m_max": [23.1, 19.4, 24.0],
    "temperature_2m_min": [14.2, 13.8, 12.9]
  }
}
```

Notes: `timezone=auto` makes Open-Meteo infer the IANA timezone from the
lat/lon and return local-time timestamps — convenient, but the response
echoes back a timezone string; don't forward it into the UI (§2a). Rate
limit: documented free-tier soft cap ~10,000 calls/day/IP, far beyond a
30-minute-poll widget's needs (48/day).

**WMO weather code → description/icon mapping** (Open-Meteo's own
documented `weather_code` table, WMO WW codes):

| Code | Description | Category |
|---|---|---|
| 0, 1 | Clear sky, Mainly clear | clear |
| 2 | Partly cloudy | cloudy (partly) |
| 3 | Overcast | cloudy |
| 45, 48 | Fog, Depositing rime fog | fog |
| 51, 53, 55 | Drizzle: light / moderate / dense | rain |
| 56, 57 | Freezing drizzle: light / dense | rain/ice |
| 61, 63, 65 | Rain: slight / moderate / heavy | rain |
| 66, 67 | Freezing rain: light / heavy | rain/ice |
| 71, 73, 75, 77 | Snow fall: slight / moderate / heavy; snow grains | snow |
| 80, 81, 82 | Rain showers: slight / moderate / violent | rain |
| 85, 86 | Snow showers: slight / heavy | snow |
| 95, 96, 99 | Thunderstorm: slight/moderate; with slight hail; with heavy hail | thunder |

This collapses cleanly onto the 7 categories `iconFor()` already handles by
substring match on wttr.in's English condition text (`thunder`, `snow`,
`rain`/`drizzle`/`shower`, `fog`/`mist`/`haze`, `overcast`, `cloudy`,
`clear`/`sunny`). §5: build a `code → category` lookup for numeric WMO
codes and feed the category string into the existing `iconFor()`, rather
than a second icon-selection function.

### wttr.in (current approach)

`?format=j1` returns a much larger JSON document than the `%C|%t` format
string currently used. Confirmed structure:

- `current_condition[0]`: `temp_C`, `temp_F`, `FeelsLikeC`, `FeelsLikeF`,
  `humidity`, `weatherCode`, `weatherDesc[0].value`, `cloudcover`,
  `pressure`, `precipMM`, `windspeedKmph`, `uvIndex`, `observation_time`.
- `weather[]` — one entry per forecast day (3 by default), each with
  `date`, `maxtempC`, `mintempC`, `astronomy[0]` (`sunrise`, `sunset`, …),
  and an `hourly[]` breakdown.
- `nearest_area[0]` — `areaName[0].value`, `region[0].value`,
  `country[0].value`, `latitude`, `longitude`. **This is a leak risk in its
  own right**: even if the widget only reads `current_condition`/`weather`,
  the full `j1` response in memory (or a verbatim-cached file) contains the
  resolved place name and coordinates. If kept as a fallback, parse out
  only the needed fields and never persist the raw response.
- A lighter `format=j2` variant drops hourly data.

Reliability/rate limits: no formally documented rate limit; it's a single
community-run box (`wttr.in`/`wttr.is`, same backend, kept in sync for
redundancy) — no SLA, documented past outages. Fine as a fallback source
precisely *because* it needs no coordinates (bare `wttr.in` triggers IP
geolocation server-side), which is also why it's wrong under a tunnel (§3).
HTTPS is supported — the current widget's plain `curl -s` without
`https://` should become `https://wttr.in` regardless of chosen provider.

### met.no / Yr (briefly)

`https://api.met.no/weatherapi/locationforecast/2.0/compact?lat={lat}&lon={lon}`.
No API key, but the ToS require every client to send a descriptive
`User-Agent` identifying the app and a contact method; a generic/fake UA
gets throttled (429) or denied outright on some endpoints. Coordinates-only
input (no city-name resolution, no IP fallback) is a point in its favor for
reading (b) — it can't silently degrade to IP geolocation the way wttr.in
does, since it has none. 10-day hourly forecast, `relativeHumidity` per
timestep like Open-Meteo. Reasonable second choice; held back here only by
the mandatory UA/contact-info maintenance burden with no real benefit over
Open-Meteo.

### OpenWeatherMap (briefly)

Requires an API key (free tier, needs signup). JSON, humidity and forecast
available, HTTPS. No adoption reason here — "no key, no account" is the
whole point, and Open-Meteo covers every needed field already.

### Comparison table

| | Open-Meteo | wttr.in (`j1`) | met.no/Yr | OpenWeatherMap |
|---|---|---|---|---|
| API key | none | none | none | **required** |
| Humidity | yes (`relative_humidity_2m`) | yes (`humidity`) | yes | yes |
| 3-day forecast | yes (`forecast_days=3`) | yes (3 days default) | yes (10-day, hourly) | yes |
| Rate limit | ~10k/day/IP (generous) | undocumented, best-effort | UA-gated, else 429 | tier-based |
| HTTPS | yes | yes (`https://wttr.in`) | yes | yes |
| What the provider learns | the lat/lon you send, rounded as you choose | your **IP**, used server-side to geolocate, unless you pass coords yourself | lat/lon + an identifying UA string | lat/lon or city + your account-tied API key |

---

## 2. "Use the current location but NOT REVEAL IT" — both readings

### (a) Don't display it (screenshot/stream-safe)

A typical weather UI leaks location through more surfaces than the obvious
"city name label":

- **Place name / region / country strings** — never render
  `nearest_area`/reverse-geocoded city text anywhere, including tooltips or
  debug overlays.
- **Raw coordinates** — same leak, different format; never print lat/lon.
- **Sunrise/sunset times** — look innocuous but are a real geolocation
  oracle: sunrise/sunset time + date narrows latitude worldwide, and a
  displayed UTC offset narrows it further. **Omit sunrise/sunset entirely**,
  or show only a qualitative day/night icon, never clock times.
- **Timezone abbreviation or UTC offset** — same leak category; don't
  surface `Europe/Berlin`/`CEST`, even though Open-Meteo's `timezone=auto`
  puts it right in the response.
- **A "local" landmark icon or flag**, **wind direction vs. real geographic
  features**, "distance to nearest station," or any other field implicitly
  encoding place — stick to the plain numeric/glyph set in §5.

Practical rule: the panel's data model should carry only `temp`,
`feelsLike`, `humidity`, `conditionCode`, and a 3-entry forecast array of
`{day, hi, lo, code}` — if a field isn't in that list it never reaches QML
`Text`/`Image`, a stronger guarantee than "remember not to bind it."

### (b) Don't leak it to the provider

- **IP-based geolocation** (wttr.in's default, bare-hostname behavior)
  discloses the user's public IP to wttr.in's backend on every poll, which
  resolves it to a city via a third-party GeoIP database — the status quo
  today, and the thing "NOT REVEAL IT" most directly pushes back on.
- **Coordinate rounding** is the practical lever once sending lat/lon
  directly (Open-Meteo, met.no). Real-world radius per decimal place of a
  degree (equator; longitude precision shrinks further by `cos(latitude)`
  at higher latitudes — worst-case/upper bound):

  | Decimal places | ≈ Precision |
  |---|---|
  | 0 | ≈ 111 km |
  | 1 | ≈ 11.1 km |
  | **2** | **≈ 1.1 km** |
  | 3 | ≈ 111 m |
  | 4 | ≈ 11.1 m |
  | 5 | ≈ 1.1 m |

  **2 decimal places (~1.1 km)** is the right default: still resolves to
  the correct forecast grid cell (Open-Meteo's model itself is multi-km
  resolution, so no quality lost) while collapsing "which building" to
  "which neighborhood." Round in QML (`Math.round(lat * 100) / 100`)
  before the value enters a URL string — never round only in a display
  layer after the precise value already went over the network.
- **Querying via an already-configured tunnel**: when Tor/WireGuard/
  ProtonVPN is up, the HTTPS request rides it too (`tor-router.service` is
  a transparent proxy redirecting all traffic, per `05-network-tunnels.md`),
  hiding the requesting IP from the provider. Helps (b), hurts correctness
  for IP-geolocation providers — exactly the conflict §3 covers.
- **Caching** reduces how often the provider sees the user — a 30-minute
  poll with a disk-backed cache (§4) is already conservative.
- **Is any provider meaningfully better on logging?** None publish a
  no-logs guarantee. Open-Meteo's policy says no personal-data use for
  advertising, no account required; met.no is a Norwegian government
  institute (more accountable, but still logs by IP and requires an
  identifying UA). What *you* send (rounded coordinates, no PII, HTTPS)
  matters more than provider choice — none is provably better.

### Where (a) and (b) conflict

They don't conflict on input — coordinate rounding satisfies (b) without
touching what's displayed. The one place they pull apart is
**sunrise/sunset**: a nice "comprehensive" touch, harmless to the
*provider* (it already has the coordinates), but it hands a screenshot
viewer a geolocation oracle, harming (a). Recommendation: drop
sunrise/sunset; (a) — never reveal it to whoever's looking at the widget —
is the harder constraint and wins.

---

## 3. The VPN/Tor complication

### Confirmed behavior

`toggles/toggle-tor.sh` starts/stops `tor-router.service`, a transparent
proxy that rewrites iptables/nftables rules to redirect **all** traffic
through Tor (per `05-network-tunnels.md`, not a per-app SOCKS switch).
`toggle-vpn.sh` brings up/down a `wg0` WireGuard interface via `wg-quick`;
`toggle-protonvpn.sh` brings up/down a `proton0` interface via the
`protonvpn` CLI. Any of the three changes the *apparent* egress IP for
every process on the machine, Quickshell included.

IP-based geolocation (wttr.in's bare-hostname mode, or any "resolve city
from my IP" step) necessarily returns **the tunnel exit node's location**,
not the physical machine's. Turn on ProtonVPN to an exit in another
country, and the current widget silently starts showing that country's
weather — no error, no indication anything changed, just
correct-but-wrong data. A real bug, not theoretical, given the owner
actively toggles all three tunnels.

### Options evaluated

**Fixed configured coarse location.** Stable under any tunnel state since
it never touches the network to determine "where am I" — just a stored
value. Downside: doesn't follow travel; needs a manual update (via a toggle
script, not QML writing config) when the owner is actually elsewhere for an
extended period.

**GeoClue2** — confirmed installed (`geoclue 2.8.2-1`). `systemctl status
geoclue` shows the unit present and `activatable` (D-Bus-activated,
correctly `inactive (dead)` until requested — not a sign of breakage).
`/usr/lib/geoclue-2.0/demos/` contains `agent` and `where-am-i`, confirming
demo tooling is present.

D-Bus API (`man 5 geoclue` + installed `geoclue.conf`): service
`org.freedesktop.GeoClue2`, object `/org/freedesktop/GeoClue2/Manager`,
interface `...Manager` with `CreateClient()` → a client object path. That
`Client` interface exposes `DesktopId` (must be set — how geoclue
authorizes the caller), a settable `RequestedAccuracyLevel`,
`Start()`/`Stop()`, and a `LocationUpdated(old, new)` signal; the resulting
`Location` object exposes `Latitude`, `Longitude`, `Accuracy` (meters),
`Altitude`, `Timestamp`.

Accuracy levels — pulled via `strings` on the installed `where-am-i` demo
binary (not guessed): **`COUNTRY`=1, `CITY`=4, `NEIGHBORHOOD`=5,
`STREET`=6, `EXACT`=8** (implicit `NONE`=0). Request `CITY` — no need for
street-level precision, and it caps what the app ever receives.

Positioning source: this machine's `/etc/geoclue/geoclue.conf` has `[wifi]`
enabled by default, resolving via an Ichnaea-compatible API — Arch's
default build point is `https://api.beacondb.net/v1/geolocate` (BeaconDB,
community successor to Mozilla Location Service). GeoClue's WiFi source
does make its own outbound call, but its *input* (nearby WiFi AP
BSSIDs/signal strengths) is read locally off the WiFi hardware regardless
of tunnel state — the tunnel only affects which network path carries that
query to BeaconDB, not what physical APs were scanned. This is the core
reason GeoClue fixes §3: **its accuracy is independent of VPN/Tor state**,
unlike IP geolocation, which *is* the tunnel's exit node by construction.
`[ip]` (GeoIP) is also enabled locally as one of several sources GeoClue
blends (GPS > WiFi > 3G > IP preference) — on this laptop the WiFi source
should dominate.

**Authorization caveat, found locally**: `geoclue.conf`'s `[agent]`
whitelist only lists `geoclue-demo-agent;gnome-shell;
io.elementary.desktop.agent-geoclue2;sm.puri.Phosh;lipstick` — a standalone
Quickshell process isn't on it. Fix with a one-time root-level config
change (an install step, not a QML runtime write): add a
`[<quickshell-desktop-id>]` section with `allowed=true` to
`/etc/geoclue/geoclue.conf`, or a drop-in under `/etc/geoclue/conf.d/`.

Also confirmed: geoclue has a **static-source** (`[static-source]`, reading
`/etc/geolocation` — plain text `latitude`/`longitude`/`altitude`/
`accuracy-radius`, one per line, watched live) — an OS-level way to
implement "fixed coarse location" *through* GeoClue itself. Simpler here,
though, to keep the override as its own toggle-managed value than add a
second geoclue config surface to maintain.

**Timezone-derived coarse fallback.** `timedatectl show -p Timezone` (zero
network calls, fully offline) returns e.g. `Europe/Berlin`. Mapping that to
an approximate lat/lon (a static IANA-zone → centroid table bundled with
the widget) gives a "roughly which region" answer with no network
dependency — the right fallback when GeoClue is unavailable and no
override is set, since it degrades gracefully instead of falling through
to IP geolocation.

**Manual override.** Simplest, most predictable; belongs in
`toggles/toggle-weather-location.sh` (never QML writing config), storing a
rounded coordinate pair the widget reads at startup.

### Recommended layered strategy (precedence, highest first)

1. Manual override, if set.
2. GeoClue2 at `CITY` accuracy, if the D-Bus service answers and the app is
   authorized.
3. Timezone-derived centroid, if GeoClue is unavailable.
4. IP geolocation (current wttr.in default) — last resort only, flagged
   ("approx.", no place named) since it's silently wrong under a tunnel.

Check tunnel state cheaply by reusing this repo's own convention:
`toggles/toggle-tor.sh get`, `toggle-vpn.sh get`, `toggle-protonvpn.sh get`
each print `on`/`off` (`toggles/lib.sh`'s `toggle_get` contract). Rule to
add on top: **if any of the three report `on`, skip tier 4 entirely** and
fall to the timezone centroid instead — not actively misleading.

---

## 4. Quickshell implementation shape

**Fetch mechanism**: keep the existing `Quickshell.Io.Process` + `curl` +
`StdioCollector` pattern already in `Weather.qml` — matches every other
network-touching widget in this repo, and both surveyed upstreams that
fetch JSON do the same via subprocess rather than in-QML networking:
**end-4/dots-hyprland** runs `Process` → `bash -c "curl -s wttr.in/...
?format=j1 | jq '{...}'"` parsed via `StdioCollector.onStreamFinished`,
nearly identical to this repo's current widget; **caelestia-dots/shell**
and **DankMaterialShell** use a `Requests.get(url, onSuccess, onError,
headers)` helper (their own thin wrapper, still shelling out under the
hood) rather than raw QML `XMLHttpRequest`. `XMLHttpRequest` does work
inside Quickshell's JS engine and would avoid a `curl` process per poll,
but isn't this repo's established pattern, and `curl --max-time` already
gives a clean timeout — no reason to switch fetch mechanisms for this
widget.

`Quickshell.FileView` is the right tool for **disk caching**: write the
last successful, already-rounded/trimmed data to
`~/.cache/quickshell/weather.json` after each fetch, read it back via
`FileView` on `Component.onCompleted` so a restart shows last-known data
immediately instead of a blank widget.

**Error/stale-data handling**: this shell has a documented "full offline
mode"; the existing widget's `visible: ready` gate hides it entirely until
first successful fetch. For a comprehensive panel, prefer degrading over
disappearing: on fetch failure, keep showing cached values with a
staleness cue (dimmed text, or a relative "updated Nm ago" — never a clock
time, per §2a) rather than hiding once there's been one successful fetch.
Only fall back to hiding when there's no cache at all (first run, offline
immediately after install).

**Poll interval**: keep 30 minutes — weather doesn't move fast enough to
justify more, and less-frequent polling respects both providers' free
tiers and reduces how often the provider sees a request (§2b). Location
re-resolution (GeoClue/tunnel-state check) piggybacks on the same timer.

**Other Quickshell configs surveyed** (repo + exact file path + provider +
whether they hardcode a location):

| Shell | Weather file | Provider | Location |
|---|---|---|---|
| caelestia-dots/shell | `services/Weather.qml` | Open-Meteo forecast; `ip-api.com` for IP auto-location; `nominatim.openstreetmap.org` reverse geocoding for display name; `geocoding-api.open-meteo.com` city→coords | `GlobalConfig.services.weatherLocation` (city name or `"lat,lon"`); IP-API auto-detect if unset |
| end-4/dots-hyprland | `dots/.config/quickshell/ii/services/Weather.qml` | wttr.in (`curl ?format=j1` piped through `jq`) | `QtPositioning.PositionSource` (GeoClue on Linux) when GPS enabled, else a configured city name |
| AvengeMedia/DankMaterialShell | `.../Widgets/Weather.qml` + `Services/WeatherService.qml` + `Services/LocationService.qml` | Open-Meteo forecast, geocoding via `geocoding-api.open-meteo.com` | Delegated to their own **DMS** companion Go daemon over its own IPC (`"location"` subscription) — resolved outside the QML tree |
| noctalia-dev/noctalia-shell | no `Weather.qml`/service found in current `main` (C++ rewrite) tree | — | — |

Notably: **end-4's shell already uses `QtPositioning.PositionSource`**,
which on Linux resolves through GeoClue — confirming GeoClue-backed location
is an established ecosystem pattern, not novel here. `QtPositioning` is a
higher-level alternative to raw `org.freedesktop.GeoClue2` D-Bus calls;
either works, but raw D-Bus (via `Quickshell.Io.Process` + `busctl`/`gdbus`,
matching this repo's subprocess pattern) avoids pulling in the
`QtPositioning` module for one widget.

---

## 5. Panel design

Layout for a hover panel (opens on hover per this repo's constraint, never
click) matching the existing pywal-only `Commons/Color.qml`/`Style.qml`
token system, no hardcoded colors/sizes:

```
┌─────────────────────────────┐
│  󰖐  21°C  (feels 21°C)       │  ← icon + temp + feels-like
│  Overcast · 58% humidity     │  ← condition text + humidity, plain text
├─────────────────────────────┤
│  Mon    Tue    Wed           │  ← 3-day row
│  󰖙      󰖗      󰖕            │
│  23/14  19/14  24/13         │  ← hi/lo
└─────────────────────────────┘
```

No place name, no coordinates, no sunrise/sunset row, no timezone string —
per §2a. Day labels use relative/short weekday names (`Mon`/`Tue`/`Wed`,
derived from `Date`, not from any provider field), never a date that could
be cross-referenced with other leaked timing info.

**Nerd Font glyph mapping** — the existing `iconFor()` in `Weather.qml`
(lines 18–32) is **already cmap-verified against `0xProto Nerd Font`** and
carries an explicit scar tissue comment: an earlier guessed codepoint here
silently resolved to `md-numeric_5_box_multiple`, not a weather icon at
all, and was only caught by a font-cmap verification pass, not visually.
**Reuse and extend this function rather than replacing it.** Its current
mapping (verified, safe to keep as-is):

| Category | Glyph | Codepoint |
|---|---|---|
| thunder | 󰙾 | U+F067E |
| snow/sleet/ice | 󰖘 | U+F0598 |
| rain/drizzle/shower | 󰖗 | U+F0597 |
| fog/mist/haze | 󰖑 | U+F0591 |
| overcast (and unrecognized fallback) | 󰖐 | U+F0590 |
| cloudy/partly cloudy | 󰖕 | U+F0595 |
| clear/sunny | 󰖙 | U+F0599 |

To extend `iconFor()` for numeric WMO codes (§1) rather than the current
substring-matched English text, add a small `code → category` lookup onto
the same seven strings `iconFor()` already switches on (`"thunder"`,
`"snow"`, `"rain"`, `"fog"`, `"overcast"`, `"cloudy"`, `"clear"`) and pass
the category string into the existing function unchanged — one verified
glyph table, not a second parallel icon map.

**Any glyph beyond the seven already in `iconFor()`** (heavy/light snow
split, a dedicated hail icon, a day/night pair) is **out of scope to
hardcode here** — only *candidate* codepoints are listed above. Per this
repo's hard-won convention, **every new codepoint must be verified against
`0xProto Nerd Font`'s actual cmap with `fontTools`
(`TTFont(...).getBestCmap()`) before use**, never assumed correct because
it "looks right" in an editor or cheat-sheet screenshot — exactly the
failure mode behind the `md-numeric_5_box_multiple` bug this file's own
comment warns about. Treat extra glyphs as a follow-up, not something
bolted on speculatively here.

**Settings persistence**: any new setting (location override, unit
preference, forecast-row visibility) goes through a `toggles/toggle-*.sh`
script — never a QML `FileView` *write*. `FileView` read-only for the
weather *data cache* (§4) is a separate concern and is fine.


---

## 6. SPEC expansion (2026-09-01): hourly + richer current conditions

The SPEC grew after this document's first draft:

> on the weather display i also want an hourly prediction. so current
> weather (with temp, humidity, sun, uv levels, wind, wind direction etc)
> temp and humid and rain change per hour for the day and then the 3 day
> temp+sky (sunny,rain,windy) forecast

**All of it is available from Open-Meteo in a single request.** Verified
live against `api.open-meteo.com` with dummy coordinates (HTTP 200, every
field present, units returned inline). This is the strongest remaining
argument for Open-Meteo over wttr.in: three tiers of data, one call, no key.

### 6a. Field mapping

| SPEC item | Open-Meteo field | Block | Unit (from `*_units`) |
| --- | --- | --- | --- |
| temp | `temperature_2m` | current | °C |
| feels-like | `apparent_temperature` | current | °C |
| humidity | `relative_humidity_2m` | current | % |
| "sun" (sky clarity) | `cloud_cover` | current | % |
| UV level | `uv_index` | current | index (unitless) |
| wind speed | `wind_speed_10m` | current | km/h |
| wind gusts | `wind_gusts_10m` | current | km/h |
| wind direction | `wind_direction_10m` | current | degrees |
| rain now | `precipitation` | current | mm |
| pressure | `surface_pressure` | current | hPa |
| day/night icon variant | `is_day` | current | 0/1 |
| **hourly temp** | `temperature_2m` | hourly | °C |
| **hourly humidity** | `relative_humidity_2m` | hourly | % |
| **hourly rain** | `precipitation` + `precipitation_probability` | hourly | mm / % |
| hourly icon | `weather_code` | hourly | WMO |
| 3-day sky | `weather_code` | daily | WMO |
| 3-day temp | `temperature_2m_max` / `_min` | daily | °C |
| 3-day rain | `precipitation_sum`, `precipitation_probability_max` | daily | mm / % |
| 3-day "windy" | `wind_speed_10m_max` | daily | km/h |
| 3-day UV | `uv_index_max` | daily | index |

### 6b. Three things the mapping does not solve for you

**1. "Windy" is not a WMO weather code.** The `weather_code` enum covers
clear/cloud/fog/drizzle/rain/snow/thunderstorm — there is no windy value.
The SPEC's three-way "sunny, rain, windy" summary therefore has to be
*derived*: take `weather_code` for the sunny/rain axis, then override the
label to "windy" when `wind_speed_10m_max` crosses a threshold. Pick the
threshold explicitly rather than leaving it implicit — Beaufort 6
("strong breeze", ~39 km/h) is a defensible line, ~25-30 km/h if you want
it to trigger more readily. Document whichever is chosen in the code.

**2. `forecast_hours=24` counts from the current hour, not midnight.** The
SPEC says "per hour for the day", which is ambiguous between *the rest of
today* and *the next 24 hours*. A rolling 24h window is more useful (at
23:00 the "rest of today" view is one data point) and is what the query
above requests. If calendar-day framing is wanted instead, drop
`forecast_hours` and slice the `hourly` arrays by date. **Recommendation:
rolling 24h.**

**3. `wind_direction_10m` is degrees, not a compass point.** Map to 8 or 16
points for display (`["N","NE","E","SE","S","SW","W","NW"][Math.round(deg
/ 45) % 8]`), and/or rotate an arrow glyph. If using an arrow glyph,
remember this repo's rule: verify the codepoint against `0xProto Nerd
Font`'s cmap with `fontTools` before shipping it.

### 6c. Privacy re-check against the expanded fields

The expansion adds no place names or coordinates, so the display half of
"NOT REVEAL IT" is unaffected — with one thing to keep excluded.

- **Still never render sunrise/sunset** (`daylight_duration`,
  `sunrise`, `sunset` are all available and all must stay out). They remain
  the sharpest geolocation oracle in the API: sunrise time plus date pins
  latitude closely, and clock offset gives longitude.
- `uv_index` is a mild version of the same signal — peak UV timing tracks
  local solar noon. Showing a *current* UV number is fine; plotting a
  full-day UV curve with timestamps would leak more than intended. The
  hourly series the SPEC asks for is temp/humidity/rain, so simply do not
  add UV to the hourly chart.
- `timezone=auto` is derived server-side from the coordinates already sent;
  it discloses nothing additional to the provider. But **do not display the
  resolved timezone name** — it is a coarse location label by another name.
- The 2dp coordinate rounding (~1.1km) from §2b still applies unchanged;
  none of the new fields need finer precision.

### 6d. Panel layout implication

Three tiers of data is more than a hover panel comfortably holds at the
width the other panels use (`Display.qml` is 360px, `News` was 380px). The
hourly series in particular wants horizontal room. Options, in preference
order:

1. **Widen this panel specifically** and render the hourly series as a
   compact sparkline-style row (temp line + rain bars sharing an x-axis,
   humidity on hover) rather than 24 discrete cells.
2. Two-column layout: current conditions block on the left, hourly +
   3-day stacked on the right.
3. Tabs — rejected: a hover panel with tabs requires a click to switch,
   which fights the hover-driven interaction model.

Note this panel is a **center**-section widget, so it also inherits the
panel-anchoring problem in `07-spec-conformance.md` §4a. That constraint
should be resolved before investing in a wide, information-dense weather
panel that is awkward to reach.
