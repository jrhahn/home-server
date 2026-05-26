{ ... }:

{
  # Replace this file with the one generated on the server:
  #
  #   sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
  #
  # Keep this placeholder only so the repository evaluates before installation.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
