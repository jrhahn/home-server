{ config, lib, pkgs, server, ... }:

{
  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud32;
    hostName = server.cloudDomain;
    home = "/srv/nextcloud";
    https = server.enablePublicTls;

    database.createLocally = true;
    configureRedis = true;
    maxUploadSize = "16G";
    autoUpdateApps.enable = true;

    config = {
      dbtype = "pgsql";
      adminuser = "admin";
      adminpassFile = "/var/lib/secrets/nextcloud-admin-pass";
    };

    settings = {
      default_phone_region = "DE";
      trusted_domains = [
        server.cloudDomain
        "family-server.local"
      ];
      overwriteprotocol = lib.mkIf server.enablePublicTls "https";
      maintenance_window_start = 2;
      log_type = "file";
    };

    phpOptions = {
      "opcache.interned_strings_buffer" = "16";
    };
  };

  services.nginx.virtualHosts.${server.cloudDomain} = lib.mkIf server.enablePublicTls {
    enableACME = true;
    forceSSL = true;
  };
}
