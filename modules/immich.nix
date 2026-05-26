{ config, server, ... }:

{
  services.immich = {
    enable = true;
    host = "127.0.0.1";
    port = 2283;
    mediaLocation = "/srv/immich";
    openFirewall = false;

    machine-learning.enable = true;

    environment = {
      IMMICH_LOG_LEVEL = "warn";
    };
  };

  services.redis.servers.immich.logLevel = "warning";

  hardware.graphics.enable = true;
  services.immich.accelerationDevices = null;
  users.users.immich.extraGroups = [
    "video"
    "render"
  ];

  services.nginx.virtualHosts.${server.photosDomain} = {
    enableACME = server.enablePublicTls;
    forceSSL = server.enablePublicTls;

    locations."/" = {
      proxyPass = "http://${config.services.immich.host}:${toString config.services.immich.port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = ''
        client_max_body_size 50000M;
        proxy_read_timeout   600s;
        proxy_send_timeout   600s;
        send_timeout         600s;
      '';
    };
  };
}
