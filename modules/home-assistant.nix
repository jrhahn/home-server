{ config, lib, server, ... }:

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
