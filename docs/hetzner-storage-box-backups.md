# Hetzner Storage Box Backups

This server can send a second Borg backup copy to a Hetzner Storage Box. Keep
the Storage Box coordinates in Nix and keep credentials in root-owned files
under `/var/lib/secrets`.

All Borg credentials, repo URLs, and SSH options live in the NixOS config
([modules/maintenance.nix](../modules/maintenance.nix)), derived from the
`server.backups.hetzner` settings in your private `local.nix` (schema in
[modules/options.nix](../modules/options.nix)). The
`services.borgbackup.jobs` module bakes them into a per-job wrapper for every
job, so manual operations need no environment setup:

```bash
sudo borg-job-family-hetzner <borg-subcommand>
sudo borg-job-home-assistant-hetzner <borg-subcommand>
```

`.envrc` therefore only exports `HOME_SERVER_FLAKE` as a convenience for
`nixos-rebuild`; it intentionally does not duplicate the Borg settings.

## Storage Box Setup

1. Enable SSH support for the Storage Box in Hetzner Console.
2. Create local Borg credentials:

   ```bash
   ./scripts/create-hetzner-borg-secrets.sh
   ```

3. Add the printed public key to the Storage Box `authorized_keys` file.
   Hetzner expects normal OpenSSH format for port `23`.
4. Edit your private `local.nix`:

   ```nix
   server.backups.hetzner = {
     enable = true;
     user = "uXXXXX";
     host = "uXXXXX.your-storagebox.de";
     # repoPrefix, sshKeyFile, and passphraseFile have sane defaults; override
     # only if needed (see modules/options.nix).
   };
   ```

## Initialize Repositories

Apply the NixOS configuration first so the job wrappers exist:

```bash
sudo nixos-rebuild switch --flake <your-private-config>#family-server
```

The jobs default to `doInit = true`, so each remote repository is created
automatically on its first run. If you want to create them up front (e.g. to
confirm SSH access to the Storage Box before the first scheduled run), use the
generated wrappers — they already carry the repo URL, SSH key, and passphrase:

```bash
sudo borg-job-family-hetzner init --encryption=repokey-blake2 --remote-path=borg-1.4
sudo borg-job-home-assistant-hetzner init --encryption=repokey-blake2 --remote-path=borg-1.4
```

## Manual Runs

Start a remote backup immediately:

```bash
sudo systemctl start borgbackup-job-family-hetzner.service
sudo systemctl start borgbackup-job-home-assistant-hetzner.service
```

List remote archives:

```bash
sudo borg-job-family-hetzner list
sudo borg-job-home-assistant-hetzner list
```

## Restore Drill

At least once, restore a few files into `/tmp/restore-test`:

```bash
sudo mkdir -p /tmp/restore-test
cd /tmp/restore-test
sudo borg-job-family-hetzner extract ::ARCHIVE_NAME srv/immich-originals
```

Replace `ARCHIVE_NAME` with one from `sudo borg-job-family-hetzner list`.

Keep an offline copy of `/var/lib/secrets/borg-hetzner-passphrase`. Without it,
the encrypted remote repository is not useful during disaster recovery.

## ai-trainer, which lives on another host

`server.backups.aiTrainer` collects ai-trainer's backup from the VPS it runs on
and drops it in `/srv/backups/ai-trainer`, which is one of the family job's
paths — so it rides along to the Storage Box with everything else, under the
same encryption and retention.

```nix
server.backups.aiTrainer = {
  enable = true;              # requires backups.hetzner.enable
  host = "trainlikea.pro";
};
```

It is a **pull**, and that is the reason it is done from here rather than from
the VPS. A host that pushes its own backups needs credentials for the backup
store, so whoever takes that host also reaches the backups of the data it was
holding — the one failure a backup exists to survive. This way the VPS holds no
Storage Box credentials; this machine reaches in and collects. The cost is that
this machine has to be up, which the staleness check below covers.

The VPS takes its own backup at 03:00 on its own timer; `fetch-ai-trainer-backup`
collects at 03:30, before the 04:00 local job. It is deliberately not hooked into
the Borg jobs' `preHook`s: that would run a `pg_dump` on a production host twice
a night, once per job.

Two things keep this from being a root shell on that host:

- the key's forced command there is ai-trainer's `scripts/backup-over-ssh.sh`,
  which permits `rsync --server --sender` against the backup directory and
  nothing else — it cannot take a backup, delete one, write into the directory,
  or read any other path;
- the artefacts arrive already encrypted with their own GPG passphrase, which
  this machine does not have. So it stores ai-trainer's secrets bundle without
  being able to read it, and a compromise of this machine or of the Storage Box
  does not yield that deployment's encryption keys.

### Setup

```bash
# here
sudo ssh-keygen -t ed25519 -N "" -f /var/lib/secrets/ai-trainer-backup-ed25519
sudo cat /var/lib/secrets/ai-trainer-backup-ed25519.pub
```

On the VPS, in `/root/.ssh/authorized_keys`, as one line:

```
command="/opt/ai-trainer/scripts/backup-over-ssh.sh",restrict ssh-ed25519 AAAA... backup-fetch
```

Then check it end to end before trusting the timer:

```bash
sudo systemctl start fetch-ai-trainer-backup.service
sudo ls -l /srv/backups/ai-trainer
```

### A stale fetch is a failure, not a shrug

`fetch-ai-trainer-backup` exits non-zero if nothing in the local directory is
newer than two days, and mails through `ai-trainer-backup-failed.service`.
Without that, a broken timer on the VPS would be invisible: the fetch would
succeed against a stale directory, Borg would archive last week's artefacts every
night and report success, and the first time anybody noticed would be a restore.

The restore procedure for those artefacts is `docs/runbook-restore.md` in the
ai-trainer repo. A dump without the keys that open it restores *cleanly* and is
useless, so that document matters more than this section does.
