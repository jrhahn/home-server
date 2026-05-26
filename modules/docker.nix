{ pkgs, ... }:

{
  # Escape hatch for future services that do not have a good NixOS module.
  # Nextcloud and Immich are configured natively in this repository.
  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    docker
    docker-compose
  ];
}
