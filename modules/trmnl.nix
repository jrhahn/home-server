{
  lib,
  pkgs,
  server,
  ...
}:

let
  cfg = server.trmnl;

  image = "ghcr.io/usetrmnl/terminus:${cfg.imageTag}";

  # Terminus' own defaults; the image EXPOSEs 2300. The database and key/value
  # ports are only ever used inside the Podman network.
  port = 2300;

  # Web and worker are the same image with the same wiring; only the command
  # and the one-shot setup step differ.
  sharedEnvironment = {
    HANAMI_PORT = toString port;
    # Terminus builds the image URLs it hands to the device from this, so it
    # must be the address the *device* uses, not the one an admin browser uses.
    API_URI = cfg.apiUri;
  };

  # oci-containers orders units but cannot wait for readiness the way upstream's
  # compose does with `condition: service_healthy`. On a first boot Postgres
  # spends several seconds initialising while `hanami db migrate` fails
  # immediately against it, and systemd's default rate limit (5 starts per 10s,
  # restarting after 100ms) would burn through the retries and leave the unit
  # dead. Back off and let it keep trying instead.
  startUntilDependenciesAreReady = {
    serviceConfig.RestartSec = "10s";
    startLimitIntervalSec = 0;
  };

  sharedVolumes = [
    "/srv/trmnl/uploads:/app/public/uploads"
    # The same directory mounted twice, as upstream's compose does with a single
    # named volume: Terminus serves uploaded fonts over HTTP from public/fonts,
    # and fontconfig — used by ImageMagick and headless Chromium when rendering
    # a screen — only looks in /usr/share/fonts.
    "/srv/trmnl/fonts:/app/public/fonts"
    "/srv/trmnl/fonts:/usr/share/fonts/terminus"
  ];
in
lib.mkIf cfg.enable {
  systemd.services.podman-network-trmnl = {
    description = "Create Podman network for Terminus";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network inspect trmnl >/dev/null 2>&1 || ${pkgs.podman}/bin/podman network create trmnl
    '';
  };

  # Upstream ships named volumes, which Docker seeds with the image's ownership
  # on first use. Bind mounts get no such copy-up, so every directory has to be
  # created with the uid the container runs as:
  #   postgres:18-alpine  uid/gid 70   (VOLUME /var/lib/postgresql)
  #   valkey:9.1-alpine   uid 999, gid 1000
  #   terminus            uid/gid 1000 ("app", see the project's Dockerfile)
  # uploads/cache exists in the image but the bind mount would hide it, so it is
  # created here too.
  systemd.tmpfiles.rules = [
    "d /srv/trmnl 0755 root root -"
    "d /srv/trmnl/database 0750 70 70 -"
    "d /srv/trmnl/keyvalue 0750 999 1000 -"
    "d /srv/trmnl/uploads 0750 1000 1000 -"
    "d /srv/trmnl/uploads/cache 0750 1000 1000 -"
    "d /srv/trmnl/fonts 0750 1000 1000 -"
  ];

  virtualisation.oci-containers.containers = {
    trmnl-database = {
      image = "postgres:18.6-alpine";
      pull = "newer";
      # POSTGRES_PASSWORD, and the DATABASE_URL that has to agree with it.
      environmentFiles = [ cfg.secretsFile ];
      environment = {
        POSTGRES_USER = "terminus";
        POSTGRES_DB = "terminus";
      };
      volumes = [ "/srv/trmnl/database:/var/lib/postgresql" ];
      networks = [ "trmnl" ];
    };

    trmnl-keyvalue = {
      image = "valkey/valkey:9.1-alpine";
      pull = "newer";
      volumes = [ "/srv/trmnl/keyvalue:/data" ];
      networks = [ "trmnl" ];
      # noeviction is not optional: Sidekiq keeps its queues here and silently
      # loses jobs if Valkey is allowed to evict keys under memory pressure.
      # No requirepass, matching seafile-redis in this repo — the port is never
      # published and only containers on the trmnl network can reach it.
      # Snapshots only (no appendonly), so Borg never reads a file that Valkey
      # is rewriting underneath it.
      cmd = [
        "valkey-server"
        "--maxmemory"
        "512mb"
        "--maxmemory-policy"
        "noeviction"
      ];
    };

    trmnl-web = {
      inherit image;
      pull = "newer";
      dependsOn = [
        "trmnl-database"
        "trmnl-keyvalue"
      ];
      # APP_SECRET (session encryption), DATABASE_URL, KEYVALUE_URL.
      environmentFiles = [ cfg.secretsFile ];
      environment = sharedEnvironment // {
        # Compiles assets and applies pending database migrations before Puma
        # comes up. Upstream sets this on the web service only, so the worker
        # can never race the migration.
        APP_SETUP = "true";
      };
      # Unlike every other service here, the client is a battery-powered e-paper
      # device that cannot join the tailnet, so this listens on the LAN rather
      # than on loopback behind nginx. See server.trmnl.listenAddress.
      ports = [ "${cfg.listenAddress}:${toString port}:${toString port}" ];
      volumes = sharedVolumes;
      networks = [ "trmnl" ];
      # Upstream's `init: true`. Terminus renders screens by driving headless
      # Chromium, which forks freely; without an init process to reap them the
      # container slowly fills with zombies.
      extraOptions = [ "--init" ];
    };

    trmnl-worker = {
      inherit image;
      pull = "newer";
      dependsOn = [ "trmnl-web" ];
      environmentFiles = [ cfg.secretsFile ];
      environment = sharedEnvironment;
      cmd = [
        "bundle"
        "exec"
        "sidekiq"
        "-r"
        "./config/sidekiq.rb"
      ];
      volumes = sharedVolumes;
      networks = [ "trmnl" ];
      extraOptions = [ "--init" ];
    };
  };

  # Same guard as seafile.nix: /srv may be relocated onto the external disk with
  # nofail, and if that disk is missing Podman happily bind-mounts an empty
  # directory instead of failing — which here would mean Postgres initialising a
  # second, empty database on the internal disk.
  systemd.services.podman-trmnl-database = {
    after = [ "podman-network-trmnl.service" ];
    requires = [ "podman-network-trmnl.service" ];
    unitConfig.RequiresMountsFor = [ "/srv/trmnl/database" ];
  };

  systemd.services.podman-trmnl-keyvalue = {
    after = [ "podman-network-trmnl.service" ];
    requires = [ "podman-network-trmnl.service" ];
    unitConfig.RequiresMountsFor = [ "/srv/trmnl/keyvalue" ];
  };

  systemd.services.podman-trmnl-web = {
    after = [
      "podman-network-trmnl.service"
      "podman-trmnl-database.service"
      "podman-trmnl-keyvalue.service"
    ];
    requires = [ "podman-network-trmnl.service" ];
    unitConfig.RequiresMountsFor = [ "/srv/trmnl/uploads" ];
  }
  // startUntilDependenciesAreReady;

  systemd.services.podman-trmnl-worker = {
    after = [
      "podman-network-trmnl.service"
      "podman-trmnl-web.service"
    ];
    requires = [ "podman-network-trmnl.service" ];
    unitConfig.RequiresMountsFor = [ "/srv/trmnl/uploads" ];
  }
  // startUntilDependenciesAreReady;

  # Admin UI over the tailnet, like the other services. The device does not use
  # this path — it talks to server.trmnl.apiUri directly.
  services.nginx.virtualHosts.${server.trmnlDomain} = {
    enableACME = server.enablePublicTls;
    forceSSL = server.enablePublicTls;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      recommendedProxySettings = true;
      extraConfig = ''
        # Custom fonts and plugin screenshots are uploaded through this path.
        client_max_body_size 64m;
      '';
    };
  };

  networking.firewall.allowedTCPPorts = lib.optionals cfg.openFirewall [ port ];
}
