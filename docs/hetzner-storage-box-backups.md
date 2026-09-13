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
