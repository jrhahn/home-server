{ pkgs, server, ... }:

{
  systemd.services.podman-network-seafile = {
    description = "Create Podman network for Seafile";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network inspect seafile >/dev/null 2>&1 || ${pkgs.podman}/bin/podman network create seafile
    '';
  };

  virtualisation.oci-containers.containers = {
    seafile-mysql = {
      image = "mariadb:10.11";
      pull = "newer";
      environmentFiles = [ "/var/lib/secrets/seafile.env" ];
      environment = {
        MARIADB_AUTO_UPGRADE = "1";
      };
      volumes = [
        "/srv/seafile-mysql:/var/lib/mysql"
      ];
      networks = [ "seafile" ];
    };

    seafile-redis = {
      image = "redis:7-alpine";
      pull = "newer";
      volumes = [
        "/srv/seafile-redis:/data"
      ];
      networks = [ "seafile" ];
      cmd = [
        "redis-server"
        "--appendonly"
        "yes"
      ];
    };

    seafile = {
      image = "seafileltd/seafile-mc:13.0-latest";
      pull = "newer";
      dependsOn = [
        "seafile-mysql"
        "seafile-redis"
      ];
      environmentFiles = [ "/var/lib/secrets/seafile.env" ];
      environment = {
        SEAFILE_MYSQL_DB_HOST = "seafile-mysql";
        SEAFILE_MYSQL_DB_PORT = "3306";
        SEAFILE_MYSQL_DB_USER = "seafile";
        SEAFILE_MYSQL_DB_CCNET_DB_NAME = "ccnet_db";
        SEAFILE_MYSQL_DB_SEAFILE_DB_NAME = "seafile_db";
        SEAFILE_MYSQL_DB_SEAHUB_DB_NAME = "seahub_db";
        CACHE_PROVIDER = "redis";
        REDIS_HOST = "seafile-redis";
        REDIS_PORT = "6379";
        SEAFILE_SERVER_HOSTNAME = server.cloudDomain;
        SEAFILE_SERVER_PROTOCOL = if server.enablePublicTls then "https" else "http";
        TIME_ZONE = "Europe/Berlin";
        ENABLE_NOTIFICATION_SERVER = "false";
        NON_ROOT = "false";
      };
      ports = [
        "127.0.0.1:8081:80"
      ];
      volumes = [
        "/srv/seafile:/shared"
      ];
      networks = [ "seafile" ];
    };
  };

  # Each container's volume source must be mounted before Podman touches it.
  # /srv/seafile may be relocated onto the external disk by
  # server.storage.externalDisk with nofail; if that disk is missing, Podman
  # bind-mounts an empty directory into the container and Seafile initialises a
  # fresh, divergent library on the internal disk rather than failing. The two
  # database directories are internal today, but declaring them keeps the guard
  # correct if they are ever relocated too. On a non-mount path the dependency
  # resolves to -.mount and costs nothing.
  systemd.services.podman-seafile-mysql = {
    after = [ "podman-network-seafile.service" ];
    requires = [ "podman-network-seafile.service" ];
    unitConfig.RequiresMountsFor = [ "/srv/seafile-mysql" ];
  };

  systemd.services.podman-seafile-redis = {
    after = [ "podman-network-seafile.service" ];
    requires = [ "podman-network-seafile.service" ];
    unitConfig.RequiresMountsFor = [ "/srv/seafile-redis" ];
  };

  systemd.services.podman-seafile = {
    after = [
      "podman-network-seafile.service"
      "podman-seafile-mysql.service"
      "podman-seafile-redis.service"
    ];
    requires = [ "podman-network-seafile.service" ];
    unitConfig.RequiresMountsFor = [ "/srv/seafile" ];
  };

  services.nginx.virtualHosts.${server.cloudDomain} = {
    enableACME = server.enablePublicTls;
    forceSSL = server.enablePublicTls;

    locations."/" = {
      proxyPass = "http://127.0.0.1:8081";
      recommendedProxySettings = true;
      extraConfig = ''
        client_max_body_size 0;
        proxy_read_timeout 310s;
        proxy_set_header Connection "";
        proxy_http_version 1.1;
      '';
    };
  };
}
