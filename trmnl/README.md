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
  threshold — the one value here with an actionable limit.

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
