{
  config,
  lib,
  pkgs,
  server,
  ...
}:

let
  forgejoAddress = "127.0.0.1";
  forgejoPort = 3001;
  protocol = if server.enablePublicTls then "https" else "http";
  actions = server.forgejo.actions;
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

      actions = lib.mkIf actions.enable {
        ENABLED = true;
        # Resolve `uses: actions/checkout@v4` against github.com for
        # compatibility with GitHub-style workflows (needs outbound internet).
        DEFAULT_ACTIONS_URL = "github";
      };
    };
  };

  # Local Actions runner. The NixOS module is Podman-aware: it points
  # DOCKER_HOST at /run/podman/podman.sock and joins the `podman` group, so
  # jobs run in containers via the already-enabled Podman backend.
  services.gitea-actions-runner = lib.mkIf actions.enable {
    package = pkgs.forgejo-runner;
    instances.default = {
      enable = true;
      name = config.networking.hostName;
      url = "http://localhost:${toString forgejoPort}";
      tokenFile = actions.tokenFile;
      labels = [
        "ubuntu-latest:docker://node:20-bookworm"
        "ubuntu-22.04:docker://node:20-bookworm"
      ];
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
