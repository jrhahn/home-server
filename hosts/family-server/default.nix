{ ... }:

let
  server = {
    adminUser = "admin";
    cloudDomain = "cloud.home.arpa";
    photosDomain = "photos.home.arpa";
    enablePublicTls = false;
  };
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
    ../../modules/docker.nix
    ../../modules/immich.nix
    ../../modules/nextcloud.nix
    ../../modules/reverse-proxy.nix
    ../../modules/storage.nix
    ../../modules/maintenance.nix
  ];

  _module.args.server = server;

  networking.hostName = "family-server";
  time.timeZone = "Europe/Berlin";

  users.users.${server.adminUser} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
    ];
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here before disabling password login on a fresh install.
    ];
  };

  security.sudo.wheelNeedsPassword = true;

  system.stateVersion = "25.11";
}
