{ server, ... }:

{
  systemd.services.docker-network-seafile = {
    description = "Create Docker network for Seafile";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker network inspect seafile >/dev/null 2>&1 || docker network create seafile
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
      extraOptions = [
        "--health-cmd=healthcheck.sh --connect --mariadbupgrade --innodb_initialized"
        "--health-interval=20s"
        "--health-timeout=5s"
        "--health-retries=10"
      ];
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

  systemd.services.docker-seafile-mysql = {
    after = [ "docker-network-seafile.service" ];
    requires = [ "docker-network-seafile.service" ];
  };

  systemd.services.docker-seafile-redis = {
    after = [ "docker-network-seafile.service" ];
    requires = [ "docker-network-seafile.service" ];
  };

  systemd.services.docker-seafile = {
    after = [
      "docker-network-seafile.service"
      "docker-seafile-mysql.service"
      "docker-seafile-redis.service"
    ];
    requires = [ "docker-network-seafile.service" ];
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
