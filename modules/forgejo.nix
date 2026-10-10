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
  # Job images pinned by digest, never the moving tag (supply chain). Bump only
  # to a digest that is at least 3 days old; both built 2026-08-15.
  act2404 = "ghcr.io/catthehacker/ubuntu:act-24.04@sha256:62d572b92f9f32d3427b6d220ad1f9dca9c7b6ffad37d295425037dbff78abaf";
  act2204 = "ghcr.io/catthehacker/ubuntu:act-22.04@sha256:f5f5c29208c4fd541704fe7b8df33d3bf620ce4ac46f36853b7abeb0159705c4";
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

        # Git-SSH laeuft auf Forgejos eingebautem Server auf 2222, nicht ueber
        # den System-sshd auf 22. Grund: Tailscale SSH (siehe base.nix) faengt
        # Port 22 auf der Tailnet-IP ab. Je nach ACL vergibt es dort eine Shell
        # als `forgejo` oder lehnt ab -- in beiden Faellen kommt Forgejos forced
        # command nie zum Zug und Git ueber das Tailnet schlaegt fehl. Port 2222
        # bleibt davon unberuehrt, ohne dass der Notzugang ueber Tailscale SSH
        # angetastet werden muss.
        START_SSH_SERVER = true;
        SSH_PORT = 2222;
        SSH_LISTEN_PORT = 2222;
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
      # The runner hands this URL to jobs as GITHUB_SERVER_URL (checkout, API),
      # so it must be reachable from inside the job containers; localhost is
      # the container itself there. Changing it needs a re-registration: the
      # module only re-registers on new labels or token, so remove
      # /var/lib/gitea-runner/default/.runner and restart the runner.
      url = "${protocol}://${server.gitDomain}";
      tokenFile = actions.tokenFile;
      # catthehacker's act images carry what GitHub-hosted runners have (jq,
      # sudo, build-essential, python, …), so GitHub-style workflows run
      # without installing their basics first; node:20-bookworm lacked e.g.
      # jq, which subosito/flutter-action needs.
      labels = [
        "ubuntu-latest:docker://${act2404}"
        "ubuntu-24.04:docker://${act2404}"
        "ubuntu-22.04:docker://${act2204}"
      ];
      # One job at a time. Two (Rust release build + Flutter tests, ~2 GB
      # each) got OOM-killed together inside forgejo-jobs.slice's 4 GB.
      settings.runner.capacity = 1;
      settings.container.options = lib.concatStringsSep " " [
        # Stability, not security: a job (an Android Gradle build takes 4-6 GB)
        # must not push the family services into zram. No swap, so it is
        # OOM-killed inside its container instead.
        "--memory=3g"
        "--memory-swap=3g"
        # All job containers share one memory budget (slice below). Podman puts
        # them in their own scopes, so a limit on the runner service would not
        # reach them.
        "--cgroup-parent=forgejo-jobs.slice"
        # Jobs reach Forgejo through the runner URL above; the name only
        # resolves through the host's /etc/hosts, which containers don't use.
        "--add-host=${server.gitDomain}:host-gateway"
      ];
    };
  };

  # Forgejo has no API for job logs, so the admin user reads them on disk
  # (`zstdcat` for finished jobs). The ACL grants exactly that: traverse into
  # the state dir, read actions_log, nothing else (app.ini, repos and the
  # database stay forgejo-only). d: makes new log files readable as well.
  systemd.tmpfiles.rules = lib.mkIf actions.enable [
    "a+ /srv/forgejo - - - - u:${server.adminUser}:x"
    "a+ /srv/forgejo/data - - - - u:${server.adminUser}:x"
    "A+ /srv/forgejo/data/actions_log - - - - u:${server.adminUser}:rX,d:u:${server.adminUser}:rX"
  ];

  # Joint cap for all job containers: 7.5 GB host, ~3 GB for the services.
  # Over the cap the kernel OOM-kills a job, not Home Assistant or Immich.
  # No swap, so jobs don't fill zram either.
  systemd.slices.forgejo-jobs = lib.mkIf actions.enable {
    sliceConfig = {
      MemoryMax = "4G";
      MemorySwapMax = "0";
    };
  };

  # Git-SSH (Forgejos eingebauter Server, siehe START_SSH_SERVER oben). Der
  # System-sshd auf Port 22 bleibt unveraendert.
  networking.firewall.allowedTCPPorts = [ 2222 ];

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
