# Installation

Short path from a fresh NixOS install to this home server config.

## 1. Install NixOS

Boot the new machine from the NixOS ISO, connect wired Ethernet, and install
from the CLI.

The example below assumes the target disk is `/dev/sda` and will erase it.
Check the disk name before continuing:

```bash
sudo -i
lsblk
```

Confirm the machine was booted in UEFI mode:

```bash
ls /sys/firmware/efi
```

Partition the disk:

```bash
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart ESP fat32 1MiB 513MiB
parted /dev/sda -- set 1 esp on
parted /dev/sda -- mkpart root btrfs 513MiB 100%
partprobe /dev/sda
udevadm settle
lsblk
```

Format and mount the filesystems:

```bash
mkfs.fat -F 32 -n boot /dev/sda1
mkfs.btrfs -f -L nixos /dev/sda2

mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount -o umask=077 /dev/disk/by-label/boot /mnt/boot
```

Generate and edit the initial NixOS config:

```bash
nixos-generate-config --root /mnt
nano /mnt/etc/nixos/configuration.nix
```

Make sure the initial config includes SSH, a temporary admin user, and the UEFI
bootloader:

```nix
boot.loader.systemd-boot.enable = true;
boot.loader.efi.canTouchEfiVariables = true;

networking.networkmanager.enable = true;
services.openssh.enable = true;
networking.firewall.allowedTCPPorts = [ 22 ];

users.users.admin = {
  isNormalUser = true;
  extraGroups = [ "wheel" "networkmanager" ];
  initialPassword = "changeme";
};

security.sudo.wheelNeedsPassword = false;
```

Install and reboot:

```bash
nixos-install
reboot
```

Remove the USB key during reboot. Log in as `admin` with password `changeme`,
then change the password:

```bash
passwd
```

## 2. Bootstrap Git

The final home-server config includes Git, German keyboard layout, zsh, and Oh
My Zsh. Before the repo config is applied, use a temporary shell with Git for
the first clone:

```bash
nix-shell -p git
```

## 3. Clone This Repo

On the new machine:

```bash
git clone <this-repo-url> ~/home-server
cd ~/home-server
```

## 4. Replace Hardware Config

Generate the real hardware config for the new machine:

```bash
sudo nixos-generate-config --show-hardware-config > hosts/family-server/hardware-configuration.nix
```

## 5. Edit Server Settings

Edit `hosts/family-server/default.nix`:

- add your SSH public key for `admin`
- adjust `cloudDomain`, `homeAssistantDomain`, and `photosDomain`
- keep `enablePublicTls = false`

This setup is intentionally private-only. Do not expose ports 80/443 through the
router and do not enable public ACME/HTTPS unless the architecture is reviewed
again.

## 6. Create Secrets

```bash
sudo install -d -m 0750 -o root -g root /var/lib/secrets
sudo sh -c 'openssl rand -base64 32 > /var/lib/secrets/nextcloud-admin-pass'
sudo chmod 0400 /var/lib/secrets/nextcloud-admin-pass
```

## 7. Apply NixOS Config

This applies the home-server config, including Git, German keyboard layout, zsh,
and Oh My Zsh for the `admin` user.

```bash
sudo nixos-rebuild switch --flake .#family-server
```

## 8. Initialize Backups

```bash
sudo borg init --encryption=none /srv/backups/borg-local
```

## 9. Import Home Assistant

If `.ha-import/homeassistant/` is present on this machine:

```bash
./scripts/import-home-assistant-config.sh
```

## 10. Start Tailscale

```bash
sudo tailscale up
```

## 11. Check Services

```bash
systemctl status home-assistant.service
systemctl status nextcloud-setup.service
systemctl status immich-server.service
```

Default local URLs:

- Home Assistant: `http://ha.home.arpa`
- Nextcloud: `http://cloud.home.arpa`
- Immich: `http://photos.home.arpa`
