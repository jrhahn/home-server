# Placeholder hardware config so the example flake evaluates.
#
# In your private repo, REPLACE this file with your machine's real config:
#   sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
#
# This template assumes a single disk with a `nixos` btrfs root and a `boot`
# vfat EFI partition by label.
{ ... }:

{
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };
}
