{ config, lib, server, ... }:

{
  services.immich = {
    enable = true;
    host = "127.0.0.1";
    port = 2283;
    mediaLocation = "/srv/immich-originals";
    openFirewall = false;

    machine-learning.enable = true;

    environment = {
      IMMICH_LOG_LEVEL = "warn";
      TMPDIR = "/srv/immich/tmp";
    };

    machine-learning.environment = {
      MACHINE_LEARNING_CACHE_FOLDER = lib.mkForce "/srv/immich/ml-cache";
      XDG_CACHE_HOME = lib.mkForce "/srv/immich/ml-cache";
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
