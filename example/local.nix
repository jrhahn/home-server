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

    # Optional: second backup copy to a Hetzner Storage Box.
    backups.hetzner = {
      enable = false;
      user = "u123456";
      host = "u123456.your-storagebox.de";
    };
  };
}
