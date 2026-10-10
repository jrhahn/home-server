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
  aiTrainer = server.backups.aiTrainer or { enable = false; };
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
  ++ lib.optionals server.paperless.enable [ "/srv/paperless" ]
  ++ lib.optionals server.trmnl.enable [ "/srv/trmnl" ]
  # The sensor archive. Unlike every other database here it is not dumped to a
  # file first: QuestDB's answer to "back me up while I run" is a checkpoint,
  # which holds the data directory still while it is copied and costs no second
  # copy on disk. See `questdbCheckpoint` below.
  ++ lib.optionals server.smarthomeTimeseries.enable [
    config.services.smarthome-timeseries.questdb.dataDir
  ]
  # ai-trainer runs on its own host and is in none of these paths otherwise.
  # `fetch-ai-trainer-backup` below drops its artefacts here, already encrypted
  # with their own passphrase, and they ride along with everything else.
  ++ lib.optionals aiTrainer.enable [ aiTrainer.localDir ];
  haPaths = [ "/srv/home-assistant" ];
  familyExclude = [
    # Seafile's Redis rewrites its append-only file while borg reads it, which
    # borg reports as a warning and the module turns into a failed job. The AOF
    # is only Redis' job queue/cache; the authoritative state is in the
    # MariaDB dump under /srv/backups/database-dumps.
    "pp:/srv/seafile-redis/appendonlydir"
  ]
  ++ lib.optionals server.paperless.enable [ "pp:/srv/paperless/log" ]
  # Terminus' PostgreSQL writes here continuously; the consistent copy is the
  # dump under /srv/backups/database-dumps, so the raw cluster is skipped.
  ++ lib.optionals server.trmnl.enable [ "pp:/srv/trmnl/database" ];
  # Copying a running QuestDB is a coin flip -- its write-ahead log may be
  # mid-apply -- so the copy happens between these two. `CHECKPOINT CREATE`
  # freezes the data directory; `CHECKPOINT RELEASE` lets it move again. (The
  # older spelling, `SNAPSHOT PREPARE`/`COMPLETE`, still works on 9.3.)
  questdbSql = sql: ''
    ${pkgs.curl}/bin/curl -fsS --get \
      "http://${config.services.smarthome-timeseries.questdb.httpEndpoint}/exec" \
      --data-urlencode "query=${sql}" >/dev/null
  '';
  questdbRelease = questdbSql "CHECKPOINT RELEASE";
  # A checkpoint holds QuestDB's *state*, not its files: ingest carries on and
  # appends to the newest partition's column files, which borg reports as
  # "file changed while we backed it up". That is a warning, and the NixOS
  # module fails the whole job on any warning -- leaving a complete archive
  # named `.failed`. The appended rows lie beyond what the checkpoint recorded,
  # so a restore does not see them.
  #
  # This `borg` sits in front of the real one for the jobs that carry QuestDB.
  # With BORG_EXIT_CODES=modern, 100 means "file changed and nothing else"
  # (mixed warnings come back as 1). Even then it only passes when every
  # changed file is under QuestDB's data directory; a changed file anywhere
  # else still fails the job as before.
  questdbTolerantBorg =
    let
      dataDir = config.services.smarthome-timeseries.questdb.dataDir;
    in
    pkgs.writeShellScriptBin "borg" ''
      log="$(${pkgs.coreutils}/bin/mktemp)"
      trap '${pkgs.coreutils}/bin/rm -f "$log"' EXIT
      exec 3>&1
      ${config.services.borgbackup.package}/bin/borg "$@" 2>&1 >&3 3>&- \
        | ${pkgs.coreutils}/bin/tee "$log" >&2
      rc="''${PIPESTATUS[0]}"
      if [[ "$rc" == 100 ]]; then
        changed="$(${pkgs.gnugrep}/bin/grep -c ': file changed while we backed it up$' "$log" || true)"
        elsewhere="$(${pkgs.gnugrep}/bin/grep ': file changed while we backed it up$' "$log" \
          | ${pkgs.gnugrep}/bin/grep -vc '^${dataDir}/' || true)"
        if [[ "$changed" -gt 0 && "$elsewhere" == 0 ]]; then
          echo "only QuestDB files changed during its checkpoint; not a failure" >&2
          exit 0
        fi
      fi
      exit "$rc"
    '';

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
      description = "Dump Seafile, Immich, and (when enabled) Paperless and Terminus databases";
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

        ${lib.optionalString server.trmnl.enable ''
          if ${pkgs.podman}/bin/podman ps --format '{{.Names}}' | ${pkgs.gnugrep}/bin/grep -qx trmnl-database; then
            ${pkgs.podman}/bin/podman exec trmnl-database \
              pg_dump --username=terminus terminus > "$out/terminus.sql"
          fi
        ''}
              ${pkgs.util-linux}/bin/runuser -u immich -- \
                ${config.services.postgresql.package}/bin/pg_dump immich > "$out/immich.sql"
        ${lib.optionalString server.paperless.enable ''
          ${pkgs.util-linux}/bin/runuser -u paperless -- \
            ${config.services.postgresql.package}/bin/pg_dump paperless > "$out/paperless.sql"
        ''}
              ${pkgs.findutils}/bin/find /srv/backups/database-dumps -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec ${pkgs.coreutils}/bin/rm -rf {} +
      '';
    };

  }

  {
    # The release is wired to ExecStopPost rather than to the job's postHook, and
    # that is the point of it: postHook does not run when borg fails, and a
    # checkpoint left held makes QuestDB keep every write-ahead segment from then
    # on -- a disk filling up days later, for a reason nobody connects to a backup
    # that failed one night. ExecStopPost runs either way, and releasing when
    # nothing is held answers OK, so the safety net costs nothing.
    systemd.services = lib.mkIf server.smarthomeTimeseries.enable (
      lib.genAttrs
        ([ "borgbackup-job-family-local" ] ++ lib.optional hetzner.enable "borgbackup-job-family-hetzner")
        (_: {
          serviceConfig.ExecStopPost = pkgs.writeShellScript "questdb-checkpoint-release" questdbRelease;
          path = lib.mkBefore [ questdbTolerantBorg ];
          environment.BORG_EXIT_CODES = "modern";
        })
    );

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
          ${lib.optionalString server.smarthomeTimeseries.enable (questdbSql "CHECKPOINT CREATE")}
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
          ${lib.optionalString server.smarthomeTimeseries.enable (questdbSql "CHECKPOINT CREATE")}
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

  (lib.mkIf aiTrainer.enable {
    systemd.tmpfiles.rules = [
      # 0700: the artefacts are GPG-encrypted, but the manifests beside them name
      # this deployment's schema and key fingerprints, and there is no reason for
      # anything but root to read any of it.
      "d ${aiTrainer.localDir} 0700 root root -"
    ];

    systemd.services.fetch-ai-trainer-backup = {
      description = "Fetch ai-trainer's backup artefacts from its own host";
      startAt = aiTrainer.startAt;
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      onFailure = lib.optionals (notify.enable && hetzner.enable) [
        "ai-trainer-backup-failed.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        UMask = "0077";
      };
      script = ''
        set -euo pipefail

        ssh_opts="-i ${aiTrainer.sshKeyFile} -o StrictHostKeyChecking=accept-new -o BatchMode=yes"
        remote='${aiTrainer.user}@${aiTrainer.host}'

        # Read-only from this side. The remote host takes its own backup on its
        # own timer; this only collects the result, so the key on the far end can
        # be pinned to `rsync --server --sender` and nothing else. The far end in
        # turn holds no credentials for where these end up, which is the whole
        # reason this is a pull: a compromise of the host holding the data cannot
        # reach the backups of it.
        ${pkgs.rsync}/bin/rsync \
          --archive --compress --itemize-changes \
          -e "${pkgs.openssh}/bin/ssh $ssh_opts" \
          "$remote:${aiTrainer.remoteDir}/" '${aiTrainer.localDir}/'

        # A fetch that succeeds against a stale directory is exactly the failure
        # this arrangement exists to prevent: borg would archive last week's
        # artefacts every night and report success, and the first time anyone
        # looked would be the restore. So no recent manifest is an error here,
        # where it mails, rather than a shrug.
        if [ -z "$(${pkgs.findutils}/bin/find '${aiTrainer.localDir}' \
                     -maxdepth 1 -name '*.manifest.json' -mtime -2 -print -quit)" ]; then
          echo "No ai-trainer manifest newer than two days in ${aiTrainer.localDir}." >&2
          echo "The remote host's own backup timer has not run, or produced nothing." >&2
          echo "Check: systemctl status ai-trainer-backup.timer on ${aiTrainer.host}" >&2
          exit 1
        fi

        # Bound the staging copy only. Borg keeps 7 daily / 4 weekly / 12 monthly
        # of its own, so this is about not filling a disk, not about retention.
        ${pkgs.findutils}/bin/find '${aiTrainer.localDir}' \
          -mindepth 1 -maxdepth 1 -type f -mtime +${toString aiTrainer.keepDays} -delete

        echo "ai-trainer artefacts present:"
        ${pkgs.coreutils}/bin/ls -1 '${aiTrainer.localDir}' | ${pkgs.coreutils}/bin/tail -6
      '';
    };
  })

  (lib.mkIf (aiTrainer.enable && notify.enable && hetzner.enable) {
    # Its own mail rather than a case in borg-notify@, which is parameterised on
    # borg job names and reads their units. Wired onFailure only: a nightly
    # "fetch worked" adds nothing to the backup mail that follows it half an
    # hour later, while a silent failure is the thing worth an interruption.
    systemd.services.ai-trainer-backup-failed = {
      description = "Email that fetching ai-trainer's backup failed";
      serviceConfig.Type = "oneshot";
      script = ''
        host='${config.networking.hostName}'
        when="$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S %Z')"
        result="$(${pkgs.systemd}/bin/systemctl show fetch-ai-trainer-backup.service -p Result --value)"
        errlines="$(${pkgs.systemd}/bin/journalctl -o cat -u fetch-ai-trainer-backup.service -n 40 2>/dev/null \
          | ${pkgs.coreutils}/bin/tail -n 15 || true)"

        {
          printf 'From: %s\n' '${notify.from}'
          printf 'To: %s\n' '${notify.to}'
          printf 'Subject: [BACKUP FAILED] ai-trainer fetch (%s) @ %s\n\n' "$result" "$host"
          printf 'ai-trainer backup artefacts were not fetched.\n\n'
          printf 'Remote:  %s@%s:%s\n' '${aiTrainer.user}' '${aiTrainer.host}' '${aiTrainer.remoteDir}'
          printf 'Local:   %s\n' '${aiTrainer.localDir}'
          printf 'When:    %s\n\n' "$when"
          printf 'Until this works, the family Borg job is archiving whatever is\n'
          printf 'already in the local directory -- possibly nothing, possibly old.\n'
          printf 'See docs/runbook-restore.md in the ai-trainer repo.\n\n'
          printf 'Journal:\n%s\n' "$errlines"
        } | ${pkgs.msmtp}/bin/msmtp -C /etc/msmtprc -a default '${notify.to}'
      '';
    };
  })

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
