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
  familyPaths = [
    "/var/lib/secrets"
    "/srv/backups/database-dumps"
    "/srv/forgejo"
    "/srv/immich"
    "/srv/immich-originals"
    "/srv/seafile"
    "/srv/seafile-mysql"
    "/srv/seafile-redis"
  ]
  ++ lib.optionals server.paperless.enable [ "/srv/paperless" ];
  haPaths = [ "/srv/home-assistant" ];
  familyExclude = [
    # Seafile's Redis rewrites its append-only file while borg reads it, which
    # borg reports as a warning and the module turns into a failed job. The AOF
    # is only Redis' job queue/cache; the authoritative state is in the
    # MariaDB dump under /srv/backups/database-dumps.
    "pp:/srv/seafile-redis/appendonlydir"
  ]
  ++ lib.optionals server.paperless.enable [ "pp:/srv/paperless/log" ];
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
    description = "Dump Seafile, Immich, and (when enabled) Paperless databases";
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
${lib.optionalString server.paperless.enable ''
      ${pkgs.util-linux}/bin/runuser -u paperless -- \
        ${config.services.postgresql.package}/bin/pg_dump paperless > "$out/paperless.sql"
''}
      ${pkgs.findutils}/bin/find /srv/backups/database-dumps -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec ${pkgs.coreutils}/bin/rm -rf {} +
    '';
  };

  services.borgbackup.jobs = {
    family-local = {
      paths = familyPaths;
      repo = "/srv/backups/borg-local";
      startAt = "04:00";
      compression = "zstd,6";
      encryption.mode = "none";
      exclude = familyExclude;
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
      paths = haPaths;
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
      paths = familyPaths;
      repo = hetznerRepo "family";
      startAt = "04:30";
      exclude = familyExclude;
      preHook = ''
        ${pkgs.systemd}/bin/systemctl start dump-family-service-databases.service
      '';
    };

    home-assistant-hetzner = hetznerCommon // {
      paths = haPaths;
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
          host='${config.networking.hostName}'
          result="$(${pkgs.systemd}/bin/systemctl show "$unit" -p Result --value)"
          when="$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S %Z')"

          case "$job" in
            family-hetzner)
              repo='${hetznerRepo "family"}'
              sources='${lib.concatStringsSep "\n  " familyPaths}'
              ;;
            home-assistant-hetzner)
              repo='${hetznerRepo "home-assistant"}'
              sources='${lib.concatStringsSep "\n  " haPaths}'
              ;;
            *)
              repo=""
              sources="(unknown job)"
              ;;
          esac

          if [ "$result" = "success" ]; then
            subject="[backup OK] $job @ $host"
          else
            subject="[BACKUP FAILED] $job ($result) @ $host"
          fi

          # Pull a clean summary straight from the repo: last archive details
          # plus repository totals (deduplicated size across all archives).
          export BORG_RSH='${pkgs.openssh}/bin/ssh -i ${hetzner.sshKeyFile} -o StrictHostKeyChecking=accept-new'
          export BORG_PASSCOMMAND='${pkgs.coreutils}/bin/cat ${hetzner.passphraseFile}'
          info="$(${pkgs.borgbackup}/bin/borg info --remote-path=borg-1.4 --last 1 "$repo" 2>&1 \
            | ${pkgs.gnugrep}/bin/grep -avE 'post-quantum|decrypt later|openssh.com/pq|may need to be upgraded|vulnerable' || true)"

          errlines=""
          if [ "$result" != "success" ]; then
            errlines="$(${pkgs.systemd}/bin/journalctl -o cat -u "$unit" -n 80 2>/dev/null \
              | ${pkgs.gnugrep}/bin/grep -aiE 'error|fail|denied|exception|cannot|could not|permission' \
              | ${pkgs.coreutils}/bin/tail -n 15 || true)"
          fi

          {
            printf 'From: %s\n' '${notify.from}'
            printf 'To: %s\n' '${notify.to}'
            printf 'Subject: %s\n\n' "$subject"
            printf 'Job:     %s\n' "$job"
            printf 'Result:  %s\n' "$result"
            printf 'Host:    %s\n' "$host"
            printf 'When:    %s\n' "$when"
            printf 'Repo:    %s\n\n' "$repo"
            printf 'Sources:\n  %s\n\n' "$sources"
            if [ -n "$errlines" ]; then
              printf 'Errors (from journal):\n%s\n\n' "$errlines"
            fi
            printf 'Latest archive + repository totals:\n%s\n' "$info"
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
