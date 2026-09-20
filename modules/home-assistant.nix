{
  config,
  lib,
  pkgs,
  server,
  ...
}:

let
  # Every light that can actually follow a colour temperature. Anything that is
  # only a switch (the TP-Link plugs) or has no CCT channel belongs nowhere near
  # this list -- `light.turn_on` with `kelvin` on such an entity is silently
  # ignored, which reads as "the automation does nothing" rather than as an
  # error.
  #
  # The entity ids are HA's own slugs and were never renamed along with the
  # friendly names, so the friendly name is given here for each: the ids alone
  # are unreadable, and renaming a device in the UI does not change them.
  #
  # All three LocalTuya lamps are in here now. Until the integration was moved
  # to the maintained fork they could not be: the floor lamp had no entity at
  # all, the Planon panel reported `supported_color_modes: [onoff]`, and the
  # hallway light's datapoints were mapped two off -- brightness read from the
  # on/off boolean and colour temperature from the work-mode string.
  tunableLights = [
    "light.arbeitsecke" # "Arbeitsecke" (ZHA)
    "light.test_led_stripe" # "Küche LED Streifen" -- the id is a misnomer, this is not a test rig
    "light.tz3210_xwqng7ol_ts0502b" # "LED Streifen" (ZHA)
    "light.tz3210_xwqng7ol_ts0502b_2" # "Lampe Fototapete" (ZHA)
    "light.flur_decke" # "Flur - Decke" (LocalTuya)
    "light.ldvsmart_pla45x45t" # "Küche - Decke", LEDVANCE Planon 45x45 (LocalTuya)
    "light.deckenfluter_deckenfluter" # SUN@HOME floor lamp, 2200-5000 K (LocalTuya)
  ];

  # The daily colour temperature curve.
  #
  # Brightness is deliberately not part of this. Switching on, switching off and
  # dimming are done by hand; the only thing that follows the clock is the
  # colour. Nothing here ever turns a lamp on -- see the automations below.
  #
  # Expressed in minutes since midnight rather than in whole hours so the
  # boundaries can sit anywhere; `7*60+30` for half past seven is a one-token
  # change. Kept as a single-line Jinja expression rather than an {% if %} block
  # so it renders to a native int instead of a string with stray newlines.
  #
  # The forenoon block is the point of the whole file: the flat is a shaded
  # ground floor and measures around 100 lux where the circadian consensus asks
  # for roughly 250 lux melanopic EDI -- about 300-400 lux vertically at the eye
  # -- so from 07:00 the colour sits at the top of the range. The evening ramp is
  # the other half; 5000 K at 22:00 is the part that costs sleep.
  #
  # Kelvin outside a lamp's own range is clamped by Home Assistant, so the
  # 2200 K night step is safe on any of these (they all report 2000-6535 K).
  #
  # Fed to `light.turn_on` as `color_temp_kelvin`, never as `kelvin`. The older
  # `kelvin` field is accepted without complaint and then ignored: the service
  # call succeeds, the automation records a trigger, and the lamp does not
  # change colour. Verified against this instance -- `kelvin: 4000` left the
  # light at 5025 K, `color_temp_kelvin: 4000` moved it at once.
  kelvinExpr = "{% set m = now().hour * 60 + now().minute %}{{ 2200 if m < 7*60 else 5000 if m < 11*60 else 4500 if m < 15*60 else 4000 if m < 19*60 else 3000 if m < 22*60 else 2200 }}";

  # The subset of the lights above that is switched on right now. This is what
  # keeps the schedule from ever waking anybody: at a boundary the automation
  # targets this list, and if nothing is lit the list is empty and the service
  # call does nothing at all.
  litLightsExpr = "{{ expand(${builtins.toJSON tunableLights}) | selectattr('state', 'eq', 'on') | map(attribute='entity_id') | list }}";
in
{
  services.home-assistant = {
    enable = true;
    configDir = "/srv/home-assistant";
    config = {
      http = {
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
        ];
      };

      # State history + its storage backend. This install does not pull in
      # `default_config` (which would bundle these), so enable them explicitly;
      # without them the dashboard's history-graph reports "history integration
      # disabled". recorder defaults to a local SQLite db under the (persistent)
      # config dir and records all entities.
      recorder = { };
      history = { };

      # "Birds today", which the node cannot produce itself: it has no clock
      # and no NTP, so it cannot know when a day rolls over. It publishes a
      # running total instead (`total_increasing`, counted at the arrival so
      # neither a lost QoS0 message nor the 60 s publish rate limit can drop
      # one), and the meter turns that into a per-day figure here.
      #
      # Daily rather than a template sensor over history: the raw states are
      # purged after 10 days, while a utility meter keeps its own state and its
      # own long-term statistics. The counter resetting to zero -- which it does
      # whenever the board loses power entirely, since it lives in RTC RAM --
      # is handled by the meter the same way Home Assistant handles any
      # `total_increasing` reset, without inventing a negative day.
      #
      # The source id follows Home Assistant's slugify, which transliterates:
      # `Küche` became `kuche` and `Auslöseschwelle` became `ausloseschwelle`,
      # so `Terrasse Vögel gesamt` is `sensor.terrasse_vogel_gesamt`. Worth
      # checking against the real entity the first time the node reports.
      utility_meter.terrasse_voegel_heute = {
        name = "Terrasse Vögel heute";
        source = "sensor.terrasse_vogel_gesamt";
        cycle = "daily";
      };

      # The feeder scale used to be declared here by hand, as nine MQTT
      # entities on `birds/scale/*` plus a tare script. All of it is gone: the
      # firmware retired that topic prefix when the node was renamed from
      # `draussen` to `terrasse`, and it now publishes MQTT discovery configs
      # instead, so Home Assistant creates the device itself. Nothing in this
      # file has to know the fleet's topics any more.
      #
      # The entities were left behind long after the firmware stopped feeding
      # them, which is why the e-ink panel kept saying "Meisenknödel" -- the
      # name was ours, not the node's.

      # Time-of-day colour temperature.
      #
      # The point is not the schedule but that it is the *default state* of the
      # lamps: switching a light on in the forenoon gives 5000 K without anyone
      # deciding anything. A light dose that requires a decision does not get
      # taken -- which is why this is an automation and not a therapy lamp on a
      # shelf.
      #
      # Neither automation ever switches a lamp on or off, and neither touches
      # brightness. One reacts to a lamp *being* switched on, the other only
      # addresses lamps that are already lit. On/off and dimming stay manual.
      #
      # Two automations rather than one, because the scope differs and that
      # matters: switching on a lamp should only retint *that* lamp, so a
      # colour set by hand elsewhere in the flat survives. Only a day boundary
      # retints everything that is lit.
      #
      # `from = "off"` in the trigger is not cosmetic: without it every
      # attribute change re-fires the automation -- including the change the
      # automation itself causes -- and it loops.
      automation = [
        {
          id = "licht_tagesfarbe_beim_einschalten";
          alias = "Licht: Tagesfarbe beim Einschalten";
          description = "Sets the colour temperature to match the time of day whenever a lamp is switched on. Does not touch brightness.";
          # Several lamps can come on at once (group switch, scene); queued
          # rather than single so none of them is dropped.
          mode = "queued";
          max = 10;
          triggers = [
            {
              trigger = "state";
              entity_id = tunableLights;
              from = "off";
              to = "on";
            }
          ];
          actions = [
            {
              action = "light.turn_on";
              target.entity_id = "{{ trigger.entity_id }}";
              data.color_temp_kelvin = kelvinExpr;
            }
          ];
        }
        {
          id = "licht_tagesfarbe_nachziehen";
          alias = "Licht: Tagesfarbe nachziehen";
          description = "Follows the colour temperature at the day boundaries, for lamps that are already lit.";
          mode = "single";
          triggers = [
            {
              # A restart leaves every lamp on whatever colour it held before,
              # and nothing would correct that until the next boundary -- up to
              # nine hours later for a restart just after 22:00. Worse, a
              # restart *at* a boundary loses that boundary outright: the
              # entities are not loaded yet, so they are not "on" yet and the
              # target list skips them.
              trigger = "homeassistant";
              event = "start";
            }
            {
              trigger = "time";
              # The boundaries of the curve in kelvinExpr. Change them there and
              # they have to change here too, or the colour only catches up at
              # the next boundary.
              at = [
                "07:00:00"
                "11:00:00"
                "15:00:00"
                "19:00:00"
                "22:00:00"
              ];
            }
          ];
          actions = [
            {
              # An empty list is a no-op. That is what makes 07:00 harmless
              # while the flat is still dark and everyone is asleep.
              action = "light.turn_on";
              target.entity_id = litLightsExpr;
              data.color_temp_kelvin = kelvinExpr;
            }
          ];
        }
      ];

    };

    # Main dashboard, defined in nix so it is versioned and appears
    # automatically after a rebuild (this replaces the auto-generated
    # storage dashboard). Three tabs:
    #  - "Terrasse": the feeder scale (landing view, so weight + temperature
    #    are the first thing the app shows).
    #  - "Klima": the rs-smarthome-nodes sensor fleet, one card group per room.
    #  - "Zuhause": the classic auto layout (original-states strategy, grouped by
    #    area) so the general overview is preserved and keeps updating itself.
    #
    # Entity IDs are HA's name-slugs (ö -> o), and for the MQTT-discovered nodes
    # they are "<device> <entity>" slugged together -- device "Bad" + entity
    # "Temperatur" -> sensor.bad_temperatur. If a card shows "entity not found",
    # check the real id in Developer Tools -> States and adjust here.
    lovelaceConfig = {
      title = "Zuhause";
      views = [
        {
          # The bird-feeder scale on the terrace. Every entity here is
          # MQTT-discovered: nothing about this node is declared in nix any
          # more, only where its readings belong.
          title = "Terrasse";
          path = "terrasse";
          icon = "mdi:bird";
          cards = [
            {
              type = "glance";
              title = "Vogelwaage";
              state_color = true;
              columns = 2;
              entities = [
                {
                  entity = "sensor.terrasse_gewicht";
                  name = "Gewicht";
                }
                {
                  # Length of the *last* visit, so it is stale between birds by
                  # design -- see the descriptor's note in the firmware.
                  entity = "sensor.terrasse_besuchsdauer";
                  name = "Besuch";
                }
                {
                  entity = "sensor.terrasse_temperatur";
                  name = "Temperatur";
                }
                {
                  entity = "sensor.terrasse_feuchte";
                  name = "Feuchte";
                }
                {
                  # `device_class: battery`, so this renders with Home
                  # Assistant's own battery icon. It is an estimate off the
                  # voltage -- the measurement itself is a row further down.
                  entity = "sensor.terrasse_batterie_ladestand";
                  name = "Akku";
                }
              ];
            }
            {
              type = "gauge";
              entity = "sensor.terrasse_temperatur";
              name = "Temperatur";
              unit = "°C";
              min = -10;
              max = 40;
              severity = {
                green = 0;
                yellow = 25;
                red = 32;
              };
            }
            {
              type = "history-graph";
              title = "Verlauf (24 h)";
              hours_to_show = 24;
              entities = [
                { entity = "sensor.terrasse_gewicht"; }
                { entity = "sensor.terrasse_temperatur"; }
              ];
            }
            {
              type = "entities";
              title = "Kalibrierung & Tuning";
              show_header_toggle = false;
              entities = [
                # Tarieren is a discovered `button` now, so it is a plain row.
                # The old call-service card existed only because the tare was a
                # hand-written script publishing to MQTT itself.
                { entity = "button.terrasse_tarieren"; }
                { entity = "number.terrasse_kalibrierfaktor"; }
                { entity = "number.terrasse_tara_offset"; }
                { entity = "number.terrasse_ausloseschwelle"; }
                { type = "divider"; }
                { entity = "number.terrasse_idle_intervall"; }
                { entity = "number.terrasse_aktiv_intervall"; }
                { entity = "number.terrasse_heartbeat_intervall"; }
                { entity = "switch.terrasse_deep_sleep"; }
                # The escape hatch: forgets what the node believes the broker
                # holds, so the next connect announces every entity again.
                # Needed once already — ten of fourteen announcements had
                # arrived and nothing could tell the node otherwise.
                { entity = "button.terrasse_discovery_neu_ankundigen"; }
                { type = "divider"; }
                # The measurement behind the percentage above. Worth keeping in
                # view: between 3.7 and 4.0 V lives most of the capacity and
                # almost none of the voltage swing, so the percentage is soft
                # in the middle and this is the number that is not.
                { entity = "sensor.terrasse_batterie_spannung"; }
              ];
            }
          ];
        }
        {
          # The rest of the rs-smarthome-nodes fleet. Like the terrace view
          # above, none of it is declared in nix: each node publishes MQTT
          # discovery configs and Home Assistant creates the device itself.
          # Only the dashboard is hand-written, because discovery says what an
          # entity *is*, not where it should be shown.
          #
          # One card group per node; the others follow as they are built
          # (Wohnzimmer = SCD41 CO₂ + SDS011 Feinstaub, Küche = SHT31-D).
          title = "Klima";
          path = "klima";
          icon = "mdi:home-thermometer";
          cards = [
            {
              type = "glance";
              title = "Bad";
              state_color = true;
              columns = 2;
              entities = [
                {
                  entity = "sensor.bad_temperatur";
                  name = "Temperatur";
                }
                {
                  entity = "sensor.bad_feuchte";
                  name = "Feuchte";
                }
              ];
            }
            {
              # The point of this node: the Bad has no window, so relative
              # humidity is the mould early-warning. Above ~60 % sustained is
              # worth acting on, above ~70 % is trouble.
              type = "gauge";
              entity = "sensor.bad_feuchte";
              name = "Feuchte Bad";
              unit = "%";
              min = 0;
              max = 100;
              severity = {
                green = 0;
                yellow = 60;
                red = 70;
              };
            }
            {
              type = "history-graph";
              title = "Bad — Verlauf (24 h)";
              hours_to_show = 24;
              entities = [
                { entity = "sensor.bad_temperatur"; }
                { entity = "sensor.bad_feuchte"; }
              ];
            }
            {
              type = "glance";
              title = "Schlafzimmer";
              state_color = true;
              columns = 3;
              entities = [
                {
                  entity = "sensor.schlafzimmer_co2";
                  name = "CO₂";
                }
                {
                  entity = "sensor.schlafzimmer_temperatur";
                  name = "Temperatur";
                }
                {
                  entity = "sensor.schlafzimmer_feuchte";
                  name = "Feuchte";
                }
              ];
            }
            {
              # Bedroom CO₂ as a ventilation cue. ~400 ppm is outdoor air (and
              # also the SCD41's self-calibration floor, so a fresh sensor reads
              # it whether or not the air is actually fresh); 1000 ppm is the
              # usual comfort limit, and a closed bedroom passes it overnight.
              type = "gauge";
              entity = "sensor.schlafzimmer_co2";
              name = "CO₂ Schlafzimmer";
              unit = "ppm";
              min = 400;
              max = 2000;
              severity = {
                green = 400;
                yellow = 800;
                red = 1400;
              };
            }
            {
              # The overnight rise is the point: a flat line means the room is
              # ventilated, a curve climbing until you open the window is the
              # signal this node was built for. Temperature reads warm -- the
              # SCD41's T/RH sensor compensates its own CO₂ measurement and
              # self-heats, so trust the trend rather than the absolute value.
              type = "history-graph";
              title = "Schlafzimmer — Verlauf (24 h)";
              hours_to_show = 24;
              entities = [
                { entity = "sensor.schlafzimmer_co2"; }
                { entity = "sensor.schlafzimmer_temperatur"; }
                { entity = "sensor.schlafzimmer_feuchte"; }
              ];
            }
          ];
        }
        {
          title = "Zuhause";
          path = "zuhause";
          icon = "mdi:home";
          strategy = {
            type = "original-states";
          };
        }
      ];
    };
    # LocalTuya, from nixpkgs rather than vendored into this repo.
    #
    # The copy that used to sit in home-assistant/config/custom_components was
    # rospogrigio/localtuya 5.2.3, abandoned since 2023, and it had stopped
    # working in a way that is easy to miss: its options flow raises
    # `AttributeError: property 'config_entry' ... has no setter` on any Home
    # Assistant from 2024.11 on, because assigning to `self.config_entry` in an
    # OptionsFlow is no longer allowed. The entities it had already created kept
    # running, so nothing looked broken -- but "Configure" on the integration,
    # in the UI and over the API alike, threw a 500. No device could be added or
    # edited. That is why the SUN@HOME floor lamp never made it into Home
    # Assistant and why the hallway light's brightness datapoint could not be
    # corrected.
    #
    # xZetsubou/hass-localtuya is the maintained fork, same `localtuya` domain
    # and config-entry format, so the configured devices carry over.
    customComponents = [
      pkgs.home-assistant-custom-components.localtuya
    ];

    configWritable = true;
    openFirewall = false;

    extraComponents = [
      "backup"
      "bluetooth"
      "denonavr"
      "default_config"
      "go2rtc"
      "google_translate"
      "heos"
      "met"
      "mobile_app"
      "mqtt"
      "radio_browser"
      "shopping_list"
      "ssdp"
      "sun"
      "tplink"
      "tuya"
      "usb"
      "zeroconf"
      "zha"
    ];
  };

  users.users.hass.extraGroups = [
    "dialout"
    "video"
    "render"
  ];

  services.nginx.virtualHosts.${server.homeAssistantDomain} = {
    enableACME = server.enablePublicTls;
    forceSSL = server.enablePublicTls;

    locations."/" = {
      proxyPass = "http://127.0.0.1:8123";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = ''
        proxy_buffering off;
      '';
    };
  };

  networking.firewall.allowedTCPPorts = [
    8123
  ];

  assertions = [
    {
      assertion = config.services.home-assistant.configWritable;
      message = "Migrated Home Assistant configs need a writable configDir.";
    }
  ];
}
