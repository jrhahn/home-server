{ config, pkgs, ... }:

{
  systemd.services.dump-family-service-databases = {
    description = "Dump Seafile and Immich databases";
    startAt = "03:15";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      UMask = "0077";
    };
    script = ''
      set -euo pipefail
      out="/srv/backups/database-dumps/$(${pkgs.coreutils}/bin/date -u +%Y%m%dT%H%M%SZ)"
      ${pkgs.coreutils}/bin/mkdir -p "$out"

      if ${pkgs.podman}/bin/podman ps --format '{{.Names}}' | ${pkgs.gnugrep}/bin/grep -qx seafile-mysql; then
        set -a
        . /var/lib/secrets/seafile.env
        set +a
        ${pkgs.podman}/bin/podman exec seafile-mysql mariadb-dump \
          --single-transaction \
          --quick \
          --user=root \
          --password="$MARIADB_ROOT_PASSWORD" \
          --databases ccnet_db seafile_db seahub_db > "$out/seafile.sql"
      fi

      ${pkgs.util-linux}/bin/runuser -u immich -- \
        ${config.services.postgresql.package}/bin/pg_dump immich > "$out/immich.sql"

      ${pkgs.findutils}/bin/find /srv/backups/database-dumps -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec ${pkgs.coreutils}/bin/rm -rf {} +
    '';
  };

  services.borgbackup.jobs.family-local = {
    paths = [
      "/var/lib/secrets"
      "/srv/backups/database-dumps"
      "/srv/immich"
      "/srv/immich-originals"
      "/srv/seafile"
      "/srv/seafile-mysql"
      "/srv/seafile-redis"
    ];
    repo = "/srv/backups/borg-local";
    startAt = "04:00";
    compression = "zstd,6";
    encryption.mode = "none";
    prune.keep = {
      daily = 7;
      weekly = 4;
      monthly = 6;
    };
    preHook = ''
      ${pkgs.systemd}/bin/systemctl start dump-family-service-databases.service
    '';
  };

  services.borgbackup.jobs.home-assistant-local = {
    paths = [
      "/srv/home-assistant"
    ];
    repo = "/srv/backups/borg-local";
    startAt = "03:45";
    compression = "zstd,6";
    encryption.mode = "none";
    prune.keep = {
      daily = 7;
      weekly = 4;
      monthly = 6;
    };
    preHook = ''
      ${pkgs.systemd}/bin/systemctl stop home-assistant.service
    '';
    postHook = ''
      ${pkgs.systemd}/bin/systemctl start home-assistant.service
    '';
  };
}
