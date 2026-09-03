# TRMNL screen: Zuhause

Liquid template for a Terminus extension that renders weather plus the indoor
sensors onto the 7.5" panel. Create the extension in the Terminus UI
(`Extensions` → `+`); this directory holds the parts worth version controlling.

## Extension

| Field | Value |
| ----- | ----- |
| Label | `Zuhause` |
| Name  | `zuhause` |
| Kind  | `Poll` |
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

## Exchanges

Create them in this order — the coalescer numbers `source_N` by exchange order,
and the template expects weather first.

### 1. Open-Meteo → `source_1`

No key, no account. Coordinates come from Home Assistant's own config
(`GET /api/config`), so they match the house.

- Verb: `GET`
- Template (URL):

      https://api.open-meteo.com/v1/forecast?latitude=49.8728&longitude=8.6512&timezone=Europe%2FBerlin&current=temperature_2m,relative_humidity_2m,precipitation,weather_code,is_day&hourly=temperature_2m,precipitation_probability,precipitation,weather_code,is_day&forecast_hours=12&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,sunrise,sunset&forecast_days=6

- Headers: none

### 2. Home Assistant → `source_2`

- Verb: `GET`
- Template (URL): `http://192.168.1.67:8123/api/states`
- Headers:

      {"Authorization": "Bearer <HA_LONG_LIVED_TOKEN>", "Accept": "application/json"}

Create the token in Home Assistant under profile → Security → long-lived access
tokens. It is **not** stored in this repo; it lives in Terminus' database.

`Accept` is doing double duty here. Terminus picks the response parser from that
header when present (`app/aspects/extensions/fetcher/client.rb`), which matters
if the endpoint is ever swapped for one that answers `text/plain`.

## Grayscale

The panel reports as `og_plus`, which Terminus renders at 2 bits. Quantizing a
render shows the four levels are exactly 0 / 85 / 170 / 255, so every tone in
this template is written as `#000000`, `#555555`, `#AAAAAA` or `#FFFFFF`. Landing
on a level means the quantizer never dithers, which keeps small gray text crisp
instead of speckled — re-check this with `-dither None` after changing a colour.

They carry meaning rather than decoration:

* units (`°`, `% rF`, `ppm`, `mm`) are gray while the number is black, so the
  reading carries the weight without dropping the unit;
* weather icons are black-stroked with `#AAAAAA` fills, rain and snow marks in
  `#555555`, so a cloud reads as a cloud at 32 px;
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

## Rain is graded, not just flagged

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

## Icons

The framework ships no weather icons, so the template carries its own as inline
SVG on a 24x24 viewBox, sized by the wrapper span. They are defined once via
`capture` and selected by WMO code, with `is_day` switching sun for moon — a sun
at 03:00 reads as a broken screen. That is why the hourly block of the
Open-Meteo URL requests `is_day` alongside the weather code.

## Keep the editor's skeleton

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

## Why `/api/states` and not `/api/template`

`POST /api/template` would let Home Assistant shape the payload itself, but the
exchange request builder renders every body string through Liquid before
sending it, and a Jinja template full of `{% set %}` does not survive that. A
plain `GET` sidesteps it, and 82 entities are only 36 KB.

## Rooms are derived, not listed

The template groups sensors by the first word of their `friendly_name`
(`Schlafzimmer CO₂` → `Schlafzimmer`) and picks up anything with a
`device_class` of `temperature`, `humidity`, or `carbon_dioxide`. A new sensor
appears on the panel by itself, with no edit here — which is the point, since
more are coming.

Where a room has several temperatures, the one with the shortest friendly name
wins, so `Schlafzimmer Temperatur` beats `Schlafzimmer SCD41 Temperatur`.
Sensors reading `unavailable`/`unknown` are shown as `offline` rather than
hidden, so a dead sensor is visible instead of silently missing.

## Battery and WiFi

The panel's own state is the one thing on this screen that no exchange fetches.
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
an em dash beside an unlit glyph rather than as `0 %`. The block as a whole
disappears when `extension.device` is empty, which is what a screen rendered
for a model instead of a device gets.

Both glyphs are axis-aligned rectangles on an integer grid at their final size
(26x14 and 16x14), unlike the weather icons, which are curves scaled by their
wrapper. At 14 px a stroked outline or a WiFi arc lands on half pixels, and the
antialiasing that follows is exactly what the 2-bit quantizer turns into
speckle. The battery fill sits one pixel inside the shell, which is not
cosmetic: without that gutter a black low-charge fill merges with the black
border and 20 % reads as an empty battery.

## Checking a change without the panel

A screen is just a page, so a change can be seen before it reaches the device:
render the template with any Liquid implementation, wrap the output in the
model's classes and CSS variables (both come from `https://trmnl.com/api/models`
under `og_plus`), point a headless Chromium at it with `--window-size=800,480`,
and remap the screenshot onto the four levels.

```bash
magick xc:'#000000' xc:'#555555' xc:'#AAAAAA' xc:'#FFFFFF' +append pal4.png
magick shot.png -colorspace Gray -dither None -remap pal4.png quantized.png
```

`magick identify` reporting `4c` then confirms nothing dithered.

One difference to watch for if the renderer is not Ruby's: Ruby's `split` drops
a trailing empty field, so the `acc | split: "|"` that derives the room list
yields one entry fewer there than in most other implementations — which shows
up as a nameless extra room column locally that the panel never has.
