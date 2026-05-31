{
  lib,
  server,
  ...
}:

let
  cfg = server.paperless;
  protocol = if server.enablePublicTls then "https" else "http";
  port = 28981;
in
lib.mkIf cfg.enable {
  services.paperless = {
    enable = true;
    # Bulk document store under /srv (relocated to the external disk via
    # server.storage.externalDisk); the PostgreSQL database stays internal.
    dataDir = "/srv/paperless";
    consumptionDir = "/srv/paperless/consume";
    address = "127.0.0.1";
    inherit port;
    passwordFile = cfg.passwordFile;
    database.createLocally = true;

    settings = {
      PAPERLESS_OCR_LANGUAGE = cfg.ocrLanguage;
      PAPERLESS_ADMIN_USER = "admin";
      PAPERLESS_TIME_ZONE = "Europe/Berlin";
      # Behind the reverse proxy: needed for correct links and CSRF/allowed-host
      # checks on login.
      PAPERLESS_URL = "${protocol}://${server.paperlessDomain}";
    };
  };

  services.nginx.virtualHosts.${server.paperlessDomain} = {
    enableACME = server.enablePublicTls;
    forceSSL = server.enablePublicTls;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = ''
        client_max_body_size 100M;
      '';
    };
  };
}
