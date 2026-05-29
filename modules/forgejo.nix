{ config, server, ... }:

let
  forgejoAddress = "127.0.0.1";
  forgejoPort = 3000;
  protocol = if server.enablePublicTls then "https" else "http";
in
{
  environment.systemPackages = [
    config.services.forgejo.package
  ];

  services.forgejo = {
    enable = true;
    stateDir = "/srv/forgejo";
    repositoryRoot = "/srv/forgejo/repositories";

    database = {
      type = "postgres";
      createDatabase = true;
    };

    lfs.enable = true;

    dump = {
      enable = true;
      interval = "03:30";
    };

    settings = {
      DEFAULT.APP_NAME = "Home Forgejo";

      server = {
        DOMAIN = server.gitDomain;
        ROOT_URL = "${protocol}://${server.gitDomain}/";
        HTTP_ADDR = forgejoAddress;
        HTTP_PORT = forgejoPort;
        SSH_DOMAIN = server.gitDomain;
        SSH_PORT = 22;
      };

      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
      };

      session.COOKIE_SECURE = server.enablePublicTls;
      log.LEVEL = "Warn";
    };
  };

  services.nginx.virtualHosts.${server.gitDomain} = {
    enableACME = server.enablePublicTls;
    forceSSL = server.enablePublicTls;

    locations."/" = {
      proxyPass = "http://${forgejoAddress}:${toString forgejoPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = ''
        client_max_body_size 512M;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
      '';
    };
  };
}
