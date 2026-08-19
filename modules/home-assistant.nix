{
  config,
  lib,
  server,
  ...
}:

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

      # rs-bird-scale (Meisenknödel feeder scale) MQTT entities. The firmware
      # publishes ready-to-use grams to `birds/scale/state` and °C to
      # `birds/scale/temperature`, and reads retained calibration/tuning back
      # from `birds/scale/config/*` on its next online cycle (bird visit or
      # periodic heartbeat), persisting it to its own flash.
      #
      # These are *manually configured* MQTT entities, so they only load once
      # the MQTT integration (broker connection) exists as a config entry --
      # add it once via the UI: Settings -> Devices & Services -> Add
      # Integration -> MQTT, broker 127.0.0.1:1883, user `homeassistant`
      # (see modules/mosquitto.nix). configuration.yaml itself is regenerated
      # from this attrset on every restart, so this is the only place these
      # belong.
      mqtt = {
        sensor = [
          {
            name = "Meisenknödel Gewicht";
            unique_id = "birdscale_weight";
            state_topic = "birds/scale/state";
            unit_of_measurement = "g";
            device_class = "weight";
            state_class = "measurement";
          }
          {
            name = "Meisenknödel Temperatur";
            unique_id = "birdscale_temperature";
            state_topic = "birds/scale/temperature";
            unit_of_measurement = "°C";
            device_class = "temperature";
            state_class = "measurement";
          }
        ];

        # Calibration & tuning: "optimistic" (no state_topic), published
        # retained to birds/scale/config/<key>; the device reads them back and
        # stores them in flash. Changes apply with a short delay, not instantly.
        number = [
          {
            name = "Meisenknödel Auslöseschwelle";
            unique_id = "birdscale_threshold";
            command_topic = "birds/scale/config/threshold";
            unit_of_measurement = "g";
            min = 0;
            max = 500;
            step = 1;
            mode = "box";
            retain = true;
          }
          {
            name = "Meisenknödel Kalibrierfaktor";
            unique_id = "birdscale_scale_factor";
            command_topic = "birds/scale/config/scale_factor";
            min = 1;
            max = 100000;
            step = 0.1;
            mode = "box";
            retain = true;
          }
          {
            name = "Meisenknödel Tara-Offset";
            unique_id = "birdscale_offset";
            command_topic = "birds/scale/config/offset";
            min = -8388608;
            max = 8388607;
            step = 1;
            mode = "box";
            retain = true;
          }
          {
            name = "Meisenknödel Idle-Intervall";
            unique_id = "birdscale_idle_interval";
            command_topic = "birds/scale/config/idle_interval";
            unit_of_measurement = "s";
            min = 1;
            max = 3600;
            step = 1;
            mode = "box";
            retain = true;
          }
          {
            name = "Meisenknödel Aktiv-Intervall";
            unique_id = "birdscale_active_interval";
            command_topic = "birds/scale/config/active_interval";
            unit_of_measurement = "s";
            min = 1;
            max = 3600;
            step = 1;
            mode = "box";
            retain = true;
          }
          {
            # How often to publish temperature + weight even without a visitor,
            # so HA keeps a fresh reading. Realised as a whole number of idle
            # intervals on the device.
            name = "Meisenknödel Heartbeat-Intervall";
            unique_id = "birdscale_heartbeat_interval";
            command_topic = "birds/scale/config/heartbeat_interval";
            unit_of_measurement = "s";
            min = 10;
            max = 86400;
            step = 10;
            mode = "box";
            retain = true;
          }
        ];

        # OFF keeps the device awake with Wi-Fi up (bench testing on USB); ON is
        # normal battery deep sleep. Takes effect on the next online cycle.
        switch = [
          {
            name = "Meisenknödel Deep Sleep";
            unique_id = "birdscale_deep_sleep";
            command_topic = "birds/scale/config/deep_sleep";
            payload_on = "1";
            payload_off = "0";
            retain = true;
          }
        ];
      };

      # Re-zero (tare): publishes a *fresh* retained token so each run triggers
      # a re-zero on the device's next online cycle. Run it with the pan empty.
      script.birdscale_tare = {
        alias = "Meisenknödel tarieren";
        sequence = [
          {
            service = "mqtt.publish";
            data = {
              topic = "birds/scale/config/tare";
              retain = true;
              payload = "{{ now().timestamp() | int }}";
            };
          }
        ];
      };
    };

    # Main dashboard, defined in nix so it is versioned and appears
    # automatically after a rebuild (this replaces the auto-generated
    # storage dashboard). Three tabs:
    #  - "Meisenknödel": the feeder scale (landing view, so weight + temperature
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
          title = "Meisenknödel";
          path = "meisenknoedel";
          icon = "mdi:bird";
          cards = [
            {
              type = "glance";
              title = "Meisenknödel-Waage";
              state_color = true;
              columns = 2;
              entities = [
                {
                  entity = "sensor.meisenknodel_gewicht";
                  name = "Gewicht";
                }
                {
                  entity = "sensor.meisenknodel_temperatur";
                  name = "Temperatur";
                }
              ];
            }
            {
              type = "gauge";
              entity = "sensor.meisenknodel_temperatur";
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
                { entity = "sensor.meisenknodel_gewicht"; }
                { entity = "sensor.meisenknodel_temperatur"; }
              ];
            }
            {
              type = "entities";
              title = "Kalibrierung & Tuning";
              show_header_toggle = false;
              entities = [
                { entity = "number.meisenknodel_kalibrierfaktor"; }
                { entity = "number.meisenknodel_tara_offset"; }
                { entity = "number.meisenknodel_ausloseschwelle"; }
                {
                  type = "button";
                  name = "Tarieren (Waage leer!)";
                  icon = "mdi:scale-balance";
                  action_name = "Ausführen";
                  tap_action = {
                    action = "call-service";
                    service = "script.birdscale_tare";
                  };
                }
                { type = "divider"; }
                { entity = "number.meisenknodel_idle_intervall"; }
                { entity = "number.meisenknodel_aktiv_intervall"; }
                { entity = "number.meisenknodel_heartbeat_intervall"; }
                { entity = "switch.meisenknodel_deep_sleep"; }
              ];
            }
          ];
        }
        {
          # The rs-smarthome-nodes sensor fleet. Unlike the Meisenknödel
          # entities above, these are *not* declared anywhere in nix: each node
          # publishes MQTT discovery configs and Home Assistant creates the
          # device itself. Only this dashboard view is hand-written, because
          # discovery says what an entity *is*, not where it should be shown.
          #
          # One card group per node; the others follow as they are built
          # (Schlafzimmer/Wohnzimmer = SCD41 CO₂, Küche = SDS011 Feinstaub,
          # Draußen = the feeder scale's SHT31-D).
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
