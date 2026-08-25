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

      # The rs-smarthome-nodes fleet -- including the Draußen feeder scale --
      # declares its own Home Assistant entities over MQTT auto-discovery, so
      # there is deliberately no `mqtt` block here. Each node publishes retained
      # configs to `homeassistant/<component>/<node>/<key>/config`; Home
      # Assistant creates the devices, the readings and the calibration controls
      # from those. Adding a node needs no change to this file.
      #
      # Discovery still requires the MQTT integration to exist as a config entry
      # -- add it once via the UI: Settings -> Devices & Services -> Add
      # Integration -> MQTT, broker 127.0.0.1:1883, user `homeassistant` (see
      # modules/mosquitto.nix).
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
    # Every entity below now comes from MQTT auto-discovery. IDs are HA's
    # name-slugs of "<device> <entity>" (ö -> o, ß -> ss) -- device "Bad" +
    # entity "Temperatur" -> sensor.bad_temperatur, device "Draußen" + entity
    # "Luft Feuchte" -> sensor.draussen_luft_feuchte. If a card shows "entity
    # not found", check the real id in Developer Tools -> States and adjust here.
    lovelaceConfig = {
      title = "Zuhause";
      views = [
        {
          # The feeder scale, now the "Draußen" node of the fleet: same board,
          # renamed and upgraded onto the platform firmware, so its entities come
          # from discovery rather than from a hand-written `mqtt` block.
          #
          # `Temperatur` is the DS18B20 probe at the feeder; the SHT31-D's air
          # readings are `Luft *` and live on the Klima tab, since outdoor
          # humidity is climate data rather than anything about the birds.
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
                  entity = "sensor.draussen_gewicht";
                  name = "Gewicht";
                }
                {
                  entity = "sensor.draussen_temperatur";
                  name = "Temperatur";
                }
              ];
            }
            {
              type = "gauge";
              entity = "sensor.draussen_temperatur";
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
                { entity = "sensor.draussen_gewicht"; }
                { entity = "sensor.draussen_temperatur"; }
              ];
            }
            {
              # Discovery exposes the tare as a real `button` entity, so the
              # mqtt.publish script this used to call is gone: the firmware
              # consumes the retained press itself on its next online cycle.
              type = "entities";
              title = "Kalibrierung & Tuning";
              show_header_toggle = false;
              entities = [
                { entity = "number.draussen_kalibrierfaktor"; }
                { entity = "number.draussen_tara_offset"; }
                { entity = "number.draussen_ausloseschwelle"; }
                {
                  entity = "button.draussen_tarieren";
                  name = "Tarieren (Waage leer!)";
                  icon = "mdi:scale-balance";
                }
                { type = "divider"; }
                { entity = "number.draussen_idle_intervall"; }
                { entity = "number.draussen_aktiv_intervall"; }
                { entity = "number.draussen_heartbeat_intervall"; }
                { entity = "switch.draussen_deep_sleep"; }
              ];
            }
          ];
        }
        {
          # The rs-smarthome-nodes sensor fleet. Every node publishes MQTT
          # discovery configs and Home Assistant creates the device itself; only
          # this dashboard view is hand-written, because discovery says what an
          # entity *is*, not where it should be shown.
          #
          # One card group per node; Wohnzimmer (SCD41 CO₂) and Küche (SDS011
          # Feinstaub) follow as they are built.
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
            {
              # The SHT31-D on the feeder scale. This is the reference the indoor
              # nodes are judged against -- the Bad's ventilation question is
              # whether indoor absolute humidity exceeds outdoor, so this card is
              # the other half of the Feuchte gauge above.
              #
              # A battery node that only wakes for a bird visit or a heartbeat,
              # so these update far less often than the mains nodes and a stale
              # look is normal rather than a fault.
              type = "glance";
              title = "Draußen";
              state_color = true;
              columns = 2;
              entities = [
                {
                  entity = "sensor.draussen_luft_temperatur";
                  name = "Temperatur";
                }
                {
                  entity = "sensor.draussen_luft_feuchte";
                  name = "Feuchte";
                }
              ];
            }
            {
              type = "history-graph";
              title = "Draußen — Verlauf (24 h)";
              hours_to_show = 24;
              entities = [
                { entity = "sensor.draussen_luft_temperatur"; }
                { entity = "sensor.draussen_luft_feuchte"; }
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
