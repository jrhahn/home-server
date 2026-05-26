# Installation

Short path from a fresh NixOS install to this home server config.

## 1. Install NixOS

Boot the new machine from the NixOS ISO and install NixOS normally.

Recommended first install:

- wired Ethernet
- simple ext4 or btrfs disk layout
- SSH enabled
- temporary local admin user
- local/Tailscale-only access

## 2. Clone This Repo

On the new machine:

```bash
git clone <this-repo-url> ~/home-server
cd ~/home-server
```

## 3. Replace Hardware Config

Generate the real hardware config for the new machine:

```bash
sudo nixos-generate-config --show-hardware-config > hosts/family-server/hardware-configuration.nix
```

## 4. Edit Server Settings

Edit `hosts/family-server/default.nix`:

- add your SSH public key for `admin`
- adjust `cloudDomain`, `homeAssistantDomain`, and `photosDomain`
- keep `enablePublicTls = false`

This setup is intentionally private-only. Do not expose ports 80/443 through the
router and do not enable public ACME/HTTPS unless the architecture is reviewed
again.

## 5. Create Secrets

```bash
sudo install -d -m 0750 -o root -g root /var/lib/secrets
sudo sh -c 'openssl rand -base64 32 > /var/lib/secrets/nextcloud-admin-pass'
sudo chmod 0400 /var/lib/secrets/nextcloud-admin-pass
```

## 6. Apply NixOS Config

```bash
sudo nixos-rebuild switch --flake .#family-server
```

## 7. Initialize Backups

```bash
sudo borg init --encryption=none /srv/backups/borg-local
```

## 8. Import Home Assistant

If `.ha-import/homeassistant/` is present on this machine:

```bash
./scripts/import-home-assistant-config.sh
```

## 9. Start Tailscale

```bash
sudo tailscale up
```

## 10. Check Services

```bash
systemctl status home-assistant.service
systemctl status nextcloud-setup.service
systemctl status immich-server.service
```

Default local URLs:

- Home Assistant: `http://ha.home.arpa`
- Nextcloud: `http://cloud.home.arpa`
- Immich: `http://photos.home.arpa`
