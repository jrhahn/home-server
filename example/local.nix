# Per-deployment values.
#
# In your PRIVATE repo this file holds your real Tailscale IP, SSH public keys,
# and Hetzner Storage Box coordinates. Keep it out of any repo you share.
# Actual secrets (private keys, passphrases, DB passwords) stay in
# /var/lib/secrets on the server and never go in any repo.
{
  networking.hostName = "family-server";

  server = {
    # Required: the Tailscale IP of this server.
    tailscaleAddress = "100.64.0.1";

    # Required: SSH public keys allowed to log in as the admin user.
    adminSshKeys = [
      "ssh-ed25519 AAAA...replace-me... you@example.com"
    ];

    # Optional overrides (defaults shown in modules/options.nix):
    # adminUser = "admin";
    # cloudDomain = "cloud.home.arpa";
    # enablePublicTls = false;

    # Optional: relocate bulk data (Immich originals + Seafile files) onto an
    # external disk, keeping OS/databases/caches on the internal disk. The
    # device UUID is machine-specific — keep it here in your PRIVATE config,
    # never in the shared repo. Find it with `lsblk -f` or `blkid`.
    # See scripts/migrate-to-external-disk.sh for the one-time data move.
    # storage.externalDisk = {
    #   enable = true;
    #   device = "/dev/disk/by-uuid/REPLACE-WITH-REAL-UUID";
    #   fsType = "ext4";
    # };

    # Optional: second backup copy to a Hetzner Storage Box.
    backups.hetzner = {
      enable = true;
      user = "u123456";
      host = "u123456.your-storagebox.de";
    };

    # Optional: email a summary after each Hetzner backup. The SMTP password
    # (e.g. a Gmail App Password) lives in /var/lib/secrets/msmtp-password.
    backups.notify = {
      enable = true;
      to = "me@example.com";
      from = "server@example.com";
      smtpHost = "smtp.gmail.com";
      smtpPort = 587;
      smtpUser = "server@example.com";
    };

    # Optional: fetch the ai-trainer backup from its own host and let it ride
    # along in the family Borg job. Pulled, not pushed, so that host holds no
    # Storage Box credentials — a compromise of the machine holding the data
    # cannot reach the backups of it. Requires backups.hetzner.enable, since
    # that is how the artefacts leave this machine at all.
    #
    # The remote host takes its own backup on its own timer; this only collects
    # the result, so the key below can be pinned on the far end to
    # `rsync --server --sender` (ai-trainer ships scripts/backup-over-ssh.sh).
    backups.aiTrainer = {
      enable = true;
      host = "trainlikea.pro";
      # sshKeyFile defaults to /var/lib/secrets/ai-trainer-backup-ed25519.
    };
  };
}
