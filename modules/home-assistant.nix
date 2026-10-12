{
  config,
  lib,
  pkgs,
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

      # Lamps, plugs, automations and the dashboard name things in one flat,
      # so they are the private flake's to add (its home-assistant.nix).
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
