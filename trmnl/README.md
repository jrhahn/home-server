# TRMNL screens

Liquid templates for the Terminus extensions that drive the 7.5" panel, plus the
reasoning behind why they look the way they do. Two screens live here and the
device's playlist rotates between them:

| Screen | File | Shows |
| --- | --- | --- |
| Zuhause | [zuhause.liquid](zuhause.liquid) | the one screen the panel runs: weather, the rooms, rain radar, and the panel's own battery and WiFi |
| Regenradar | [radar.liquid](radar.liquid) | optional, unused by default: the radar alone, full screen and at twice the detail |

Create the extension in the Terminus UI (`Extensions` → `+`), which has no API
for it; this directory holds the parts worth version controlling. Everything
under [The panel](#the-panel) applies to both.

Only Zuhause belongs in the playlist. A second entry would cost battery for a
reason that does not survive scrutiny — see
[What a second screen costs the battery](#what-a-second-screen-costs-the-battery)
— which is why the radar moved into the dashboard as three thumbnails instead of
rotating as its own screen.

## Screen: Zuhause

Everything on one screen, because on this device a picture change is a wake-up.
The 800x480 splits into a full-width weather header and, below it, two columns:

```
+--------+------------------------------------------------------+
| [icon] |   Fr      Sa      So      Mo      Di                 |
|        |  29° 18° 23° 14° 25° 8°  30° 12° 25° 16°             |
|  23°   +------------------------------------------------------+
| bedeckt| Stündlich                        nächste 8 Stunden   |
| aus SW | 21 ↗  22 ↗  23 ↗  00 ↗  01 ↗  02 ↗  03 ↗  04 ↗       |
| DA 15– |                                                      |
|   26°  | 23°  22°  21°  20°  20°  20°  19°  19°               |
| auf .. +------------------------------------------------------+
+--------+ Radar     130 km O/W · 165 km N/S · Bild vor 8 Min.  |
| Räume  |  vor 2 h      vor 1 h        jetzt                   |
| Wohnz. | +--------+  +--------+   +--------+                  |
| Schlafz| |        |  |        |   |        |                  |
| Küche  | |   GG   |  |   GG   |   |   GG   |                  |
| Bad    | |  +DA   |  |  +DA   |   |  +DA   |                  |
| Terras.| |   +HD  |  |   +HD  |   |   +HD  |                  |
| Panel  | +--------+  +--------+   +--------+                  |
+--------+------------------------------------------------------+
```

The current conditions are one tall narrow column on the left, spanning both
rows to its right: the five-day outlook on the first, the eight-hour strip on
the second. Below, the rooms and the radar start on the same line at about 42 % of the
screen height, and both run to the bottom edge.

Sunrise and sunset are their own line, and that line break is what makes the
column narrow. Written as one line — `Darmstadt 15°–26° · auf 06:43 · unter
20:05` — it was the widest thing in the block and dictated the width of
everything above it. Broken in two, the column fits in 148 px and the rest of
the width goes to the two rows, where it buys a column per weekday.

The hourly strip's heading is `Stündlich`, not `Heute`. At 21:00 the eight
columns run to 04:00, so half of them are tomorrow and `Heute` would simply be
wrong.

The room grid is two columns in the lower half, so five rooms and the panel tile
fill three rows exactly. It takes whatever width the radar leaves — the radar's
is fixed at 490 px because three square 152 px frames plus their separators
define it exactly, and a fixed width also makes the frames start flush under
their own divider instead of floating in the middle of a stretched column. It is a `grid`, not a flex row, and the rooms come
out of the sensor list rather than a list here, so a sixth room simply starts a
fourth row — `gap` carries both axes because `sanitize.yml` allows it while
`row-gap` and `grid-gap` are stripped.

Three lines per tile is the budget that makes three rows fit, which is why
humidity and CO2 share the last line and the two bird counters share theirs.

The temperature is `value--small`, 26 px against `value--base`'s 38 px. It spent
a revision at an overridden 22 px, until the layout freed the vertical room to
put it back. Overriding the size is safe here, unlike with the labels:
the `value` classes resolve to `--value-font-family: "Inter Variable"`, a
scalable font, and only `value--xxsmall` is switched to the bitmap `TRMNL16` on
this model. The `label` classes are the bitmap ones — those must keep their
native size. The panel's own battery and WiFi sit in
the grid as a final tile rather than on a divider: as a tile they move down with
the rooms instead of colliding with them.

### Extension

| Field | Value |
| ----- | ----- |
| Label | `Zuhause` |
| Name  | `zuhause` |
| Kind  | `Poll` |
| Mode  | `Art` — see [Text or Art for this screen](#text-or-art-for-this-screen) |
| Template | contents of [zuhause.liquid](zuhause.liquid), pasted **between** the skeleton's `<div class="layout layout--col">` and its closing tag |
| Devices | the panel |

Selecting the **device** rather than only its model is what makes the battery
and WiFi readings appear. Terminus puts the device into the Liquid context only
when it renders for a device ID, and the batch job hands one over only if the
extension has devices attached: `extension.devices.any?` picks between a job
per device and a job per model (`app/jobs/batches/extension.rb`). With models
alone, `extension.device` is an empty hash and the status block renders nothing.

Switching an existing extension over does not leave a second screen behind. The
mold builder resolves the model from the device
(`app/aspects/screens/mold_builder.rb`, falling back to `device.model_id` in
`Models::Finder`) and the upsert keys on the screen name plus that model ID, so
the same screen record is updated, the playlist entry keeps working, and
`extension.css_classes` still carries the model's classes.

### Exchanges

Create them in this order — the coalescer numbers `source_N` by exchange order,
and the template expects weather first, sensors second, radar third. Reordering
them silently swaps the data behind every `source_N` reference in the template,
which looks like a broken screen rather than a mix-up.

#### 1. Open-Meteo → `source_1`

No key, no account. Coordinates come from Home Assistant's own config
(`GET /api/config`), so they match the house.

- Verb: `GET`
- Template (URL):

      https://api.open-meteo.com/v1/forecast?latitude=49.8728&longitude=8.6512&timezone=Europe%2FBerlin&current=temperature_2m,relative_humidity_2m,precipitation,weather_code,is_day,wind_speed_10m,wind_direction_10m,wind_gusts_10m&hourly=temperature_2m,precipitation_probability,precipitation,weather_code,is_day,wind_direction_10m&forecast_hours=12&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,sunrise,sunset&forecast_days=6

- Headers: none

#### 2. Home Assistant → `source_2`

- Verb: `GET`
- Template (URL): `http://192.168.1.67:8123/api/states`
- Headers:

      {"Authorization": "Bearer <HA_LONG_LIVED_TOKEN>", "Accept": "application/json"}

Create the token in Home Assistant under profile → Security → long-lived access
tokens. It is **not** stored in this repo; it lives in Terminus' database.

`Accept` is doing double duty here. Terminus picks the response parser from that
header when present (`app/aspects/extensions/fetcher/client.rb`), which matters
if the endpoint is ever swapped for one that answers `text/plain`.

#### 3. RainViewer → `source_3`

- Verb: `GET`
- Template (URL): `https://api.rainviewer.com/public/weather-maps.json`
- Headers: none

No key and no account. The response carries both the tile host and the frames
available, so nothing about the CDN is hardcoded:

```json
{"host": "https://tilecache.rainviewer.com",
 "radar": {"past": [{"time": 1788457200, "path": "/v2/radar/491cf8b74a24"}, ...]}}
```

`past` holds 13 frames at ten-minute steps — exactly 120 minutes — which is what
makes "now / −1 h / −2 h" possible at all: indices `i0`, `i0 - 6` and `i0 - 12`,
the last landing precisely on the oldest frame kept. Both offsets are clamped at
zero, because a negative index counts from the end in Liquid and would quietly
repeat the newest frame instead of failing.

The age in the radar header is `'now' | date: '%s'` minus the frame's timestamp.
Both sides come from the same clock, so the container's timezone cancels out —
which matters, because Terminus runs on UTC and any absolute clock time derived
from a Unix timestamp would be an hour or two wrong on the panel.

### Rain is graded, not just flagged

Open-Meteo's daily `weather_code` is the most severe code of the day, so one
hour of drizzle brands the whole day as rain. A real example: 2026-09-03 came
back as code 61, "slight rain", from a `precipitation_sum` of 0.1 mm falling in
a single hour. Drawn as a plain rain cloud that is misleading, and it is the
kind of wrong nobody catches until they look out of the window.

So the rain cloud comes in three grades and the amount picks one:

| | 1 drop | 2 drops | 3 drops |
| --- | --- | --- | --- |
| per day (`precipitation_sum`) | < 1 mm | 1-5 mm | >= 5 mm |
| per hour, and now (`precipitation`) | < 0.5 mm | 0.5-2 mm | >= 2 mm |

Each day column stacks the high, the night low, and then the amount wherever
anything falls at all. The hourly strip puts its millimetres under the
temperature in the same small gray.

An earlier revision instead redrew trivial amounts as overcast. Grading keeps
the information rather than hiding it, so that rule is gone.

Verify a change to the thresholds by rendering and reading the icons back out of
the HTML rather than squinting at a 32 px glyph: count `l-1 3.2` occurrences per
`<svg>` and compare against the amounts.

### Icons

The framework ships no weather icons, so the template carries its own as inline
SVG on a 24x24 viewBox, sized by the wrapper span. They are defined once via
`capture` and selected by WMO code, with `is_day` switching sun for moon — a sun
at 03:00 reads as a broken screen. That is why the hourly block of the
Open-Meteo URL requests `is_day` alongside the weather code.

**Fills only, no strokes.** Every shape is a filled `circle`, `rect`, `path` or
`polygon`, and rays, raindrops and snowflakes are filled rectangles rather than
line strokes — a raindrop is a 1.7 x 4.8 rect with a rounded end, rotated 12°.

That is not only taste. `config/sanitize.yml` allows the `svg` element just
`height`, `width`, `x`, `y`, `version`, `viewbox` and `shape-rendering`, so a
`fill` or `stroke` written on the `<svg>` is **removed**, while the same
attribute on a child element survives. An earlier revision put
`fill="none" stroke="#000000"` on the `<svg>` and let the children inherit it:
locally that rendered a black-outlined sun with rays, but on the panel the
strokes were gone, stroke-only paths vanished entirely, and the sun arrived as a
plain gray disc. Nothing in any log mentions it.

So: outlines were dropped on purpose, and now every attribute sits where the
sanitizer cannot reach it. Verify a new icon by rendering the captures on their
own at 62 px and 28 px rather than hunting for it on the screen.

### Why `/api/states` and not `/api/template`

`POST /api/template` would let Home Assistant shape the payload itself, but the
exchange request builder renders every body string through Liquid before
sending it, and a Jinja template full of `{% set %}` does not survive that. A
plain `GET` sidesteps it, and 82 entities are only 36 KB.

### Rooms are derived, not listed

The template groups sensors by the first word of their `friendly_name`
(`Schlafzimmer CO₂` → `Schlafzimmer`) and picks up anything with a
`device_class` of `temperature`, `humidity`, `carbon_dioxide`, `pm25` or
`pm10`. A new sensor appears on the panel by itself, with no edit here — which
is the point, since more are coming.

One kind cannot be found that way. A bird counter has no `device_class` at all,
so it is matched on the name instead: a `friendly_name` containing `Vogel`
counts, and `heute` versus `total`/`gesamt` in the rest of the name decides
which of the two numbers it is. That is the only name-based rule here, and it is
a rule rather than a list so the counter can be renamed without touching this
file. Anything else without a `device_class` stays invisible on purpose —
a Home Assistant install has hundreds of entities and this screen has room for
about a dozen numbers.

Both extras print as small gray lines under the temperature, since a room's
reading is the temperature and everything else is context: `PM2.5 8 · PM10 14`
for the SDS011 in the living room, `Vögel heute 12` over `gesamt 4831` on the
terrace.

The grid order is not the derivation order. Alphabetical put `Bad` first, which
is nobody's reading order, so a preferred list — `Wohnzimmer`, `Schlafzimmer`,
`Küche`, `Bad`, `Terrasse` — is applied first and anything not on it follows
alphabetically. The derivation stays intact: a new room still appears on its
own, just at the end until it is named in the list. Names in the list have to
match the first word of the `friendly_name` exactly, umlaut included.

Reordering is not free: the tiles differ in height, so moving `Wohnzimmer` and
`Schlafzimmer` into the same row put both CO2 bars there and cost 4 px, which
came out of the row gap.

Where a room has several temperatures, the one with the shortest friendly name
wins, so `Schlafzimmer Temperatur` beats `Schlafzimmer SCD41 Temperatur`.
Sensors reading `unavailable`/`unknown` are shown as `offline` rather than
hidden, so a dead sensor is visible instead of silently missing.

### Battery and WiFi

Bottom left, as the last tile of the room grid: the panel's own state is the one
thing on this screen that no exchange fetches.
Terminus puts the device into the Liquid context itself, and the device struct
exposes exactly three keys (`app/structs/device.rb`, `liquid_attributes`):

    extension.device.id
    extension.device.battery_percentage
    extension.device.wifi_percentage

Both percentages arrive precomputed. The raw voltage, the RSSI in dBm and the
`charging` flag are all stored on the device row but never reach a template, so
a screen cannot show volts even though the device reports them.

The values are as of the device's last check-in, not of the render: the device
sends `Battery-Voltage` and `RSSI` as headers on every `/api/display` request
and `Devices::Synchronizer` writes them to its row. At a 30 minute refresh rate
a reading can be that old, which is fine for both quantities but explains a
number that looks stale right after a reboot.

`battery_percentage` has two sources. Firmware that sends a `Percent-Charged`
header wins outright. Otherwise Terminus derives the percentage from the
voltage in ten steps of 0.45 V — a plain 0 to 4.5 V ramp, not a discharge
curve:

| voltage | reads as |
| --- | --- |
| >= 4.06 V | 100 % |
| 3.61-4.05 V | 90 % |
| 3.16-3.60 V | 80 % |
| 2.71-3.15 V | 70 % |

A LiPo lives between roughly 3.3 V and 4.2 V, so on that fallback the panel
only ever shows 80, 90 or 100 %, and a cell too flat to boot would still read
70 %. Which of the two is in play is visible on the panel: a multiple of ten is
the estimate, anything else is the firmware's own reading.

`wifi_percentage` maps RSSI onto ten steps as well. The three bars group those
into the distinctions worth acting on — three bars from 60 % (RSSI >= -61 dBm),
two from 40 % (>= -70), one from 20 % (>= -90), none below that.

A reading of `0` means the column still holds its default and nothing has been
reported yet; a device at a true 0 % is not making requests. Both are drawn as
an em dash beside an unlit glyph rather than as `0 %`. The tile as a whole
disappears when `extension.device` is empty, which is what a screen rendered
for a model instead of a device gets — the rooms then simply close the gap.

Both glyphs are axis-aligned rectangles on an integer grid at their final size
(26x14 and 16x14), unlike the weather icons, which are curves scaled by their
wrapper. At 14 px a stroked outline or a WiFi arc lands on half pixels, and the
antialiasing that follows is exactly what the 2-bit quantizer turns into
speckle. The battery fill sits one pixel inside the shell, which is not
cosmetic: without that gutter a black low-charge fill merges with the black
border and 20 % reads as an empty battery.

### Wind

Two places, because there was room for two and no more.

The current conditions carry the full reading: an arrow, the direction it comes
from as one of eight sectors, and the speed — `aus SW · 12 km/h`. The hourly
strip carries direction only, as a 10 px arrow beside the hour. A wind line of
its own in the strip would have cost 14 px the header did not have; beside the
hour it costs nothing, and direction per hour is the part worth having there,
since it shows the wind backing or veering over the evening.

The arrow points **where the wind is going** (direction + 180°) while the text
says where it comes from. Both conventions are in use and mixing them silently
is a real trap, so the text spells it out with `aus`. Verified by rendering the
snippet at 0°, 45°, ... 315°: `aus 0°` must point down, `aus 270°` right.

The eight sectors come out of `wdir | plus: 22.5 | divided_by: 45.0 | floor |
modulo: 8`, which puts 199° in `S` and 227° in `SW`. Dividing by `45.0` rather
than `45` matters — integer division would collapse the sectors.

Gusts print only from 40 km/h up. Below that the mean says enough and the line
is not worth a row of the widget; above it, gusts are the number that decides
whether anything outside needs securing.

Paying for the line: the current-conditions icon went from 76 px back to 64.
It had only been enlarged to fill slack in that column, and slack loses to data.

Both readings are guarded — `{%- if cur.wind_speed_10m -%}` and
`{%- if hr.wind_direction_10m[i] -%}` — so a template pasted before the exchange
URL gains its wind parameters shows nothing rather than `aus N · 0 km/h`.
Getting the guard wrong is instructive: the first attempt closed the `if` after
the hour label's `</span>` instead of before it, so with no wind data the tag
vanished with it and the whole hourly strip collapsed into a vertical list while
the five-day row disappeared. Unbalanced markup does not fail, it re-flows.

One Liquid trap on the way: `{%- when 4 -%} S` renders as `ausS`, because the
closing `-%}` strips the space that follows it. Whitespace control inside a
`case` has to go on the outside of the branch, not the inside.

### The radar thumbnails

Three frames of 152 x 152 px in the lower right, oldest on the left, because
left to right is the direction the rain is travelling and the eye follows it
into "jetzt".

Zoom 6, 1576 m/px: a 166 x 209 px frame covers 262 x 329 km — 130 km east and
west, 165 km north and south. The frames are portrait rather than square
because the room column is the taller of the two, and a square frame left 46 px
of empty screen under the radar. Filling that with more radar beats filling it
with air, and the heading says both numbers rather than claiming a radius the
window does not have.

The width is set by what is left of it, not by the map: the
rooms need roughly 230 px for two legible columns, and 780 minus that minus the
18 px gap divides into three frames plus their separators at 166. At 172 the
rooms drop to 212 px and `55 % · 1240 ppm` starts to crowd its tile, which is
where this stops. That is less than the 200 km the standalone screen shows, and it is
the scale the place names force. At zoom 5 a frame would reach 250 km, but
Groß-Gerau then sits **4 px** from Darmstadt — inside its own cross, impossible
to draw as a separate place. Zoom 6 pushes them 8 px apart and Heidelberg 33 px
down, which is the difference between a map and a smudge. It also doubles the
resolution, so a single shower is visible instead of averaged away, and the
window happens to fall inside one tile column: two tile requests per frame
instead of four.

| | value |
| --- | --- |
| frame | 166 x 209 px = 262 x 329 km |
| scale | 1576 m/px |
| centre | 83, 105 |
| window origin in global pixels | x0 8503, y0 5461 |
| tiles | 33/21 and 33/22 at (-55, -85) and (-55, 171) |
| marks | Darmstadt 83/105, Groß-Gerau 75/101, Heidelberg 84/138 |
| column | 3 x 166 + 2 separators + 4 gaps of 8 = 532 px |

Every mark, label, tile offset and the column width move when the frame size
does — thirteen numbers, which is more than is safe by hand. The frame size has
already been changed four times in this screen's life, so the arithmetic lives
in a script rather than in a habit: it takes the template, a width and a height, computes
the window origin, the tile offsets, the three marks and their labels, asserts
that the window still falls inside a single tile column, and writes a new
template. Point it at a copy, render, and compare before overwriting anything.

One trap it removed the hard way: the radar column and the current-conditions
column both carry `flex:none`, so a script that finds "the fixed-width column"
by pattern hits the wrong one and squeezes the header instead. Anchor on
`<span>Radar</span>` and count back two lines.

Marks are 5 px crosses, deliberately not dots: a gray square of a few pixels is
exactly what a weak echo looks like, while a cross cannot be mistaken for
weather. Darmstadt gets a larger black one because Groß-Gerau is 8 px away.

Labels are the **licence plate codes** — `DA`, `GG`, `HD` — not the names.
Two characters cannot collide with each other at this scale, they leave the
picture to the weather, and anyone living here reads them without a legend.
Written out, the names had to be pushed to opposite sides of their crosses to
avoid overlapping, and `Groß-Gerau` at 66 px still came back clipped to
`roß-Gerau` by the window's `overflow: hidden`, silently. `GG` sits above its
cross rather than beside it, so that `GG` and `DA` do not run together into one
token 8 px apart.

Adding more of them is cheap in pixels but not in clarity: a version with
Frankfurt, Mainz, Mannheim and Würzburg turned the frame busy, and `MZ` landed
on top of `GG` — Mainz and Groß-Gerau are 11 px apart here. Their coordinates
are in the template's comment if it is ever worth another try.

No frame around each window, and no scale bar. But some separation is not
optional: with three borderless windows 26 px apart, the echoes run together
into one strip and it stops being clear which echo belongs to which time. A
single 1 px `#AAAAAA` rule between frames settles that without boxing anything
in.

### Text or Art for this screen

One conversion mode has to serve both the type and the radar
(`app/aspects/screens/converters/monochrome.rb`): `Text` runs
`-colorspace Gray -dither None -posterize 4`, `Art` the same with
`-dither FloydSteinberg`. Measured on one screenshot, in the radar strip alone:

| | light gray | mid | dark |
| --- | --- | --- | --- |
| `Text` | 1335 px | 1104 px | 503 px |
| `Art` | 3807 px | 1142 px | 503 px |

`Art` wins, and not by a little. The dark cores are identical to the pixel and
the mid tones differ by 3 %, but `Art` shows nearly three times the light-gray
area — and at this zoom that area is where a rain field's shape lives. Without
the dither, `posterize` drops those pixels to white and leaves the echoes as
outlines with holes in them, which reads as scattered fragments rather than as
one area of rain. That is a misleading picture, not merely a poorer one.

It costs nothing on the type. The model's screen variables switch smoothing off
(`--label-small-font-smoothing: none`), so glyphs are drawn as pure black
pixels; a dither has no intermediate tone to work on and the room numbers come
out identical in both modes. Rendered side by side there is no visible
difference in the type at all.

The earlier plan was `Text`, on the theory that dithering would stipple the
glyph edges. The measurement said otherwise, and the pixel fonts are the reason.

## Screen: Regenradar

**Optional, and not in the playlist.** The dashboard already carries the radar
as thumbnails; this is the same three frames given the whole 800x480 at zoom 6,
which is twice the resolution over a 400 km window. It is worth having for a
panel on USB power, or on a button press (`screen_forward`), where an extra
wake-up costs nothing that matters. Set it up exactly like Zuhause, with its own
extension and the RainViewer exchange as `source_1`.

Three frames side by side, oldest on the left. A single frame answers whether it
is raining; three answer where the rain is going, which is the question worth a
screen.

### Extension

| Field | Value |
| ----- | ----- |
| Label | `Regenradar` |
| Name | `regenradar` |
| Kind | `Poll` |
| Mode | `Art` — see [Why Art and not Text](#why-art-and-not-text) |
| Models | the panel's model; `Devices` is unnecessary here, nothing reads device state |
| Interval | 10 minutes, matching RainViewer's cadence |
| Template | contents of [radar.liquid](radar.liquid), pasted between the skeleton's `<div class="layout layout--col">` and its closing tag |

The screen is a second entry in the device's playlist, not a replacement:
`Playlists` → the device's playlist → `Items` → `New` → pick `Extension
Regenradar`. The panel then alternates between the two on successive wake-ups.

### Exchange: RainViewer → `source_1`

- Verb: `GET`
- Template (URL): `https://api.rainviewer.com/public/weather-maps.json`
- Headers: none

No key and no account. The response carries both the tile host and the frames
currently available, so nothing about the CDN is hardcoded in the template:

```json
{"host": "https://tilecache.rainviewer.com",
 "radar": {"past": [{"time": 1788457200, "path": "/v2/radar/491cf8b74a24"}, ...]}}
```

`past` holds 13 frames at ten-minute steps — exactly 120 minutes — which is
what makes "now / −1 h / −2 h" possible at all: indices `i0`, `i0 - 6` and
`i0 - 12`, the last landing precisely on the oldest frame kept. Both offsets are
clamped at zero, because a negative index counts from the end in Liquid and
would quietly repeat the newest frame instead of failing.

Tiles are then addressed as `{host}{path}/256/6/{x}/{y}/0/1_1.png`. The `0`
selects RainViewer's black-and-white scheme, though after grayscaling it makes
no difference which scheme is used — they converge.

The age printed in the header is `'now' | date: '%s'` minus the frame's
timestamp. Both sides come from the same clock, so the container's timezone
cancels out; that matters because Terminus runs on UTC and no absolute clock
time from a Unix timestamp would be right on the panel.

### Geometry

The house does not move, so every coordinate is a literal in the template.
Web Mercator at zoom 6 is 1576 m/px at this latitude, which is the whole reason
zoom 6 was chosen: a 254 px window spans 400 km, putting Darmstadt exactly
200 km from its left and right edge, and three of them fit across 800 px. The
window is 300 px tall because the vertical space was there — 473 km north to
south.

| | value |
| --- | --- |
| window | 254 x 300 px = 400 x 473 km |
| scale | 1576 m/px |
| scale bar | 63 px = 100 km |
| window origin in global pixels | x0 8459, y0 5416 |
| tiles | 33/21, 34/21, 33/22, 34/22 at (-11, -40), (245, -40), (-11, 216), (245, 216) |

Recompute the lot for another location or zoom with:

```python
import math
LAT, LON, Z, TILE, W, H = 49.8728, 8.6512, 6, 256, 254, 300
n = 2 ** Z * TILE
s = math.sin(math.radians(LAT))
cx = (LON + 180) / 360 * n
cy = (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * n
x0, y0 = round(cx - W / 2), round(cy - H / 2)
res = 156543.03392 * math.cos(math.radians(LAT)) / 2 ** Z          # metres per pixel
print(x0, y0, res, 100000 / res)                     # origin, scale, bar length
print(x0 // TILE, y0 // TILE, x0 // TILE * TILE - x0, y0 // TILE * TILE - y0)   # first tile
```

The same two lines applied to a city's coordinates, minus `x0`/`y0`, give its
marker position inside the window; that is where the six dots come from.

### Why Art and not Text

This is the one screen where dithering earns its keep. Terminus picks the
conversion from the extension's `Mode` (`app/aspects/screens/converters/monochrome.rb`):
`Text` runs `-colorspace Gray -dither None -posterize 4`, `Art` runs the same
with `-dither FloydSteinberg`. Rendered both ways from the same screenshot, the
difference is not cosmetic: `Text` turns each echo into a solid shape with clean
edges and drops the faintest ones altogether, while `Art` keeps them as stipple.
For a radar the extent of light rain is information, not noise. The labels and
rings look identical either way, being pure black on white with no intermediate
tone for the dither to touch.

The Zuhause screen stays on `Text` for the opposite reason: there, crisp small
type matters more than tonal range.

### Orientation

A radar image without geography is a gray blob. Six city marks, a crosshair on
Darmstadt and a 100 km scale bar do that job, all as integer rectangles with
`shape-rendering="crispEdges"`, so the orientation layer never hands the
quantizer a half tone.

An earlier revision drew dashed 100 and 200 km rings around Darmstadt instead.
They carried the scale honestly but competed with the echoes for attention on a
screen whose whole subject is faint gray shapes, and the two circles per frame
were the busiest thing on the panel. The scale bar states the same distance in a
corner and leaves the picture alone.

City names are HTML spans with a white background chip rather than SVG `<text>`:
`config/sanitize.yml` grants `text` no `paint-order` attribute, so the usual
halo trick — a fat white stroke under the glyph — would paint the outline *over*
it. A white chip is also simply more legible on top of an echo.

### The filter is only `grayscale(1)`

Deliberately nothing else. Measured on a real frame, adding `contrast(1.35)`
removes about 1300 of 10800 light-gray pixels and adds nothing to the darker
levels — it erases drizzle and calls it contrast. RainViewer's palette is
already discrete, so there is no tonal range to stretch.

### What a build costs

Twelve image requests, four tiles times three frames, fetched by the rendering
browser rather than by Terminus' exchange layer. That works because
`Screens::Shoter` waits for `network.wait_for_idle` before taking the
screenshot; without that wait a remote `<img>` would be a blank box.

## The panel

True for every screen here, not just one of them.

### Grayscale

The panel reports as `og_plus`, which Terminus renders at 2 bits. Quantizing a
render shows the four levels are exactly 0 / 85 / 170 / 255, so every tone in
this template is written as `#000000`, `#555555`, `#AAAAAA` or `#FFFFFF`. Landing
on a level means the quantizer never dithers, which keeps small gray text crisp
instead of speckled — re-check this with `-dither None` after changing a colour.

They carry meaning rather than decoration:

* units (`°`, `% rF`, `ppm`, `mm`) are gray while the number is black, so the
  reading carries the weight without dropping the unit;
* weather icons are silhouettes without any outline — clouds `#AAAAAA`, sun,
  moon, drops and flakes `#555555`, the thunderbolt black — so the parts of an
  icon separate by tone rather than by a contour;
* an hour with actual precipitation prints millimetres in `#555555`, an hour
  with only a probability prints that percentage in the lighter `#AAAAAA`, and
  an hour with neither shows a faint dot — a measurement and a mere chance of
  one should not read alike;
* in the five-day header the daily high is black and the low gray;
* a dead sensor prints `offline` in gray rather than vanishing;
* the CO2 bar fills `#555555` below 1000 ppm and black above, with a tick at the
  threshold — the one value here with an actionable limit;
* the battery fill follows the same past-the-threshold rule, `#555555` above
  20 % and black at or below, and the WiFi bars are black when lit and
  `#AAAAAA` when not, so the glyph carries the reading without the number.

### Fonts live on the classes, not on the root

The framework's pixel fonts are attached to `.label` and `.value` and their
size variants — `.screen` sets `--label-font-family: "TRMNL16"` and
`--label-small-font-family: "TRMNL12"` — and nothing sets a family on the root.
So a bare `<span>` with its own `font-size` inherits no family at all and falls
back to the browser default, which is a **serif**. On a panel of pixel type,
one serif line is instantly visible and looks like a bug.

Two ways out, both used here: prefer `class="label label--small"` over an inline
`font-size`, and where a class will not do — inside a `.label` that must not
inherit its weight, for instance — name the variables explicitly:

```css
font-family: var(--label-small-font-family);
font-size: var(--label-small-font-size);
```

Do not mix them: these are bitmap fonts cut for one size each, so `TRMNL12` at
11 px is worse than either. `var()` survives the sanitizer, which only validates
`url()` and image functions.

### Keep the editor's skeleton

A new extension arrives with this in the template field, and all three levels
matter:

```html
<div class="{{ extension.css_classes }}">
  <div class="view view--full">
    <div class="layout layout--col">
    </div>
  </div>
</div>
```

`extension.css_classes` is where Terminus injects the classes belonging to the
selected model (see `app/aspects/extensions/contextualizer.rb`). Replace the
skeleton instead of pasting inside it and the markup loses its styling context:
the build still "succeeds", producing a valid 800x480 PNG that is white on
every one of its 384000 pixels, and nothing in the web or worker log complains.
The file in this directory therefore carries no wrapper of its own.

Worth knowing for diagnosing a blank panel: a screen with content is a few KB,
an empty one is around 250 bytes.

### What a second screen costs the battery

Nothing measurable, and it is worth knowing why, because the intuition that a
constantly changing panel drains faster is wrong here.

The device wakes on its own `refresh_rate` timer and makes exactly one
`/api/display` request per wake. Terminus answers it by advancing the playlist
one item and handing back that item's image (`Screens::Interrupter` →
`Screens::Positioner`, on every request). So two screens mean the same number
of wakes as one, just a different picture each time — and e-paper draws no
current to hold an image between them.

One difference does exist. The payload names the image
`<name>-<updated_at>.png` (`Structs::Screen#image_name_with_timestamp`), which
is what lets the firmware compare against its cache — the `Image-Cached` header
it sends — and skip the download and redraw when the name is unchanged. With
two screens alternating, the name differs at every wake, so nothing is ever
skipped. With a single screen it could be skipped, but only if that screen had
not been rebuilt since the last wake, which its own schedule makes unlikely.

Download size does not change either. Converted the way the panel gets them,
the radar screen is 9.3 KB and the Zuhause screen 9.1 KB — the dither stipple
compresses well because it is sparse, and both are far below the model's
`image_size_limit` of 90000 bytes.

What the rotation does cost is freshness: with two items each screen is current
only every second wake, so at a 30 minute refresh rate you see each one about
hourly and the radar's "jetzt" frame can be over an hour old by the time you
look at it. Buying that back means raising the refresh rate, and that is the one
knob that really does cost battery, roughly linearly. The cheaper knob in the
other direction is the device's `Sleep Start` / `Sleep Stop` window, which skips
the small hours entirely.

### The height budget is 460 px, not 480

`.layout` is `height: calc(var(--screen-h) - var(--gap) * 2)` and `--gap` is
10 px on this model, so a screen has **460 px** to spend, not 480. Overflow is
not clipped at the bottom either: the layout centres its content, so 13 px too
much arrives as 7 px shaved off the top *and* the bottom — a missing line under
the last room and the weekday labels cut in half, which looks like two unrelated
bugs.

Measuring it needs care. `magick ... -trim` on a rendered screen reports the ink
that survived, so an overflowing layout measures as *fitting*. Raise the screen
variable instead and let the box grow:

```bash
# --screen-h: 900px in the harness, window 800x900
magick shot.png -trim -format "%h\n" info:
```

This layout comes to 457 px. Where it goes is worth knowing, because the
instinct when a screen looks bottom-heavy is to push the lower blocks down, and
here there is nowhere to push: the room column already ends 10 px from the
bottom edge.

Empty screen at the bottom is therefore not spare height — it is one column
being shorter than its neighbour. There were two such gaps, and neither wanted
more margin:

* under the radar, because the room column is taller. Filled by making the
  frames portrait instead of square, which spends it on radar rather than air.
* under the current conditions, because the two rows beside it are taller.
  Filled by distributing that column (`justify-content: space-between`), so the
  icon sits at the top with the five-day row and the readings at the bottom with
  the hourly strip, with the slack visible between them instead of below them.

Real air between the sections came out of the five-day row, where the daily low
moved up beside the high: 14 px freed, spent on the gaps above `Stündlich`, above
the lower row, and between the room rows. Nothing on this screen carries less
information than a margin, so margins are where the trades happen.

### Checking a change without the panel

A screen is just a page, so a change can be seen before it reaches the device:
render the template with any Liquid implementation, wrap the output in the
model's classes and CSS variables (both come from `https://trmnl.com/api/models`
under `og_plus`), point a headless Chromium at it with `--window-size=800,480`,
and remap the screenshot onto the four levels.

```bash
magick xc:'#000000' xc:'#555555' xc:'#AAAAAA' xc:'#FFFFFF' +append pal4.png
magick shot.png -colorspace Gray -dither None -remap pal4.png quantized.png
```

`magick identify` reporting `4c` then confirms nothing dithered. For the radar
screen use `-dither FloydSteinberg` instead, matching its `Art` mode, and give
Chromium `--virtual-time-budget=8000` so the twelve tiles are in place before
the shot — it has to reach the network for that, unlike the Zuhause screen.

One difference to watch for if the renderer is not Ruby's: Ruby's `split` drops
trailing empty fields, so the `acc | split: "|"` that derives the room list
yields one entry fewer there than in most other implementations. Locally that
adds a nameless room the panel never has — harmless in a row, but in the 2 x 3
grid it shifts every tile and fakes an overflow. Register a Ruby-compatible
split before trusting the preview:

```python
def ruby_split(value, sep):
    parts = str(value).split(sep)
    while parts and parts[-1] == "":
        parts.pop()
    return parts

env.filters["split"] = ruby_split
```
