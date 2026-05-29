{ pkgs, ... }:

{
  # Seafile uses Podman/OCI containers because the native NixOS module was removed in 25.11.
  # Immich and Home Assistant are configured natively in this repository.
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  environment.systemPackages = with pkgs; [
    podman
    podman-compose
  ];
}
