{
  config,
  lib,
  pkgs,
  server,
  ...
}:

let
  hetzner = server.backups.hetzner or { enable = false; };
  notify = server.backups.notify or { enable = false; };
  hetznerRepo = suffix: "ssh://${hetzner.user}@${hetzner.host}:23/./${hetzner.repoPrefix}/${suffix}";
  hetznerCommon = {
    compression = "zstd,6";
    encryption = {
      mode = "repokey-blake2";
      passCommand = "${pkgs.coreutils}/bin/cat ${hetzner.passphraseFile}";
    };
    environment = {
      BORG_RSH = "${pkgs.openssh}/bin/ssh -i ${hetzner.sshKeyFile} -o StrictHostKeyChecking=accept-new";
    };
    extraArgs = [ "--remote-path=borg-1.4" ];
    # --stats so the journal has a summary the notifier can email.
    extraCreateArgs = [ "--stats" ];
    prune.keep = {
      daily = 7;
      weekly = 4;
      monthly = 12;
    };
  };
in
lib.mkMerge [
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

  services.borgbackup.jobs = {
    family-local = {
      paths = [
        "/var/lib/secrets"
        "/srv/backups/database-dumps"
        "/srv/forgejo"
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

    home-assistant-local = {
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
  // lib.optionalAttrs hetzner.enable {
    family-hetzner = hetznerCommon // {
      paths = [
        "/var/lib/secrets"
        "/srv/backups/database-dumps"
        "/srv/forgejo"
        "/srv/immich"
        "/srv/immich-originals"
        "/srv/seafile"
        "/srv/seafile-mysql"
        "/srv/seafile-redis"
      ];
      repo = hetznerRepo "family";
      startAt = "04:30";
      preHook = ''
        ${pkgs.systemd}/bin/systemctl start dump-family-service-databases.service
      '';
    };

    home-assistant-hetzner = hetznerCommon // {
      paths = [
        "/srv/home-assistant"
      ];
      repo = hetznerRepo "home-assistant";
      startAt = "04:15";
      preHook = ''
        ${pkgs.systemd}/bin/systemctl stop home-assistant.service
      '';
      postHook = ''
        ${pkgs.systemd}/bin/systemctl start home-assistant.service
      '';
    };
  };
}

(lib.mkIf (notify.enable && hetzner.enable) (
  let
    notifyUnit = job: "borg-notify@${job}.service";
    jobs = [
      "family-hetzner"
      "home-assistant-hetzner"
    ];
  in
  {
    programs.msmtp = {
      enable = true;
      accounts.default = {
        auth = true;
        tls = true;
        host = notify.smtpHost;
        port = notify.smtpPort;
        user = notify.smtpUser;
        from = notify.from;
        passwordeval = "${pkgs.coreutils}/bin/cat ${notify.passwordFile}";
      };
    };

    systemd.services = {
      "borg-notify@" = {
        description = "Email summary for borg job %i";
        serviceConfig.Type = "oneshot";
        scriptArgs = "%i";
        script = ''
          job="$1"
          unit="borgbackup-job-$job.service"
          result="$(${pkgs.systemd}/bin/systemctl show "$unit" -p Result --value)"
          if [ "$result" = "success" ]; then
            subject="[backup OK] $job @ ${config.networking.hostName}"
          else
            subject="[BACKUP FAILED] $job ($result) @ ${config.networking.hostName}"
          fi
          stats="$(${pkgs.systemd}/bin/journalctl -u "$unit" -n 400 --no-pager 2>/dev/null \
            | ${pkgs.gnugrep}/bin/grep -aiE 'Archive name|Time \(end\)|Duration|Number of files|Original size|Compressed size|Deduplicated size|This archive|All archives' \
            | ${pkgs.coreutils}/bin/tail -n 20 || true)"
          if [ -z "$stats" ]; then
            stats="$(${pkgs.systemd}/bin/journalctl -u "$unit" -n 60 --no-pager 2>/dev/null \
              | ${pkgs.gnugrep}/bin/grep -avE 'post-quantum|decrypt later|openssh.com/pq|may need to be upgraded|vulnerable' \
              | ${pkgs.coreutils}/bin/tail -n 25 || true)"
          fi
          {
            printf 'From: %s\n' '${notify.from}'
            printf 'To: %s\n' '${notify.to}'
            printf 'Subject: %s\n\n' "$subject"
            printf 'Job:    %s\nResult: %s\nHost:   %s\n\n' "$job" "$result" '${config.networking.hostName}'
            printf '%s\n' "$stats"
          } | ${pkgs.msmtp}/bin/msmtp -C /etc/msmtprc -a default '${notify.to}'
        '';
      };
    }
    // builtins.listToAttrs (
      map (j: {
        name = "borgbackup-job-${j}";
        value = {
          onFailure = [ (notifyUnit j) ];
          onSuccess = lib.optionals notify.onSuccess [ (notifyUnit j) ];
        };
      }) jobs
    );
  }
))
]
