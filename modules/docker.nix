{ pkgs, ... }:

{
  # Seafile uses Docker because the native NixOS module was removed in 25.11.
  # Immich and Home Assistant are configured natively in this repository.
  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    docker
    docker-compose
  ];
}
