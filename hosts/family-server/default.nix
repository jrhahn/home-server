{ pkgs, ... }:

let
  server = {
    adminUser = "admin";
    cloudDomain = "cloud.home.arpa";
    homeAssistantDomain = "ha.home.arpa";
    photosDomain = "photos.home.arpa";
    # Private-only deployment: local network and Tailscale, no public HTTPS.
    enablePublicTls = false;
  };
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
    ../../modules/docker.nix
    ../../modules/home-assistant.nix
    ../../modules/immich.nix
    ../../modules/nextcloud.nix
    ../../modules/reverse-proxy.nix
    ../../modules/storage.nix
    ../../modules/maintenance.nix
  ];

  _module.args.server = server;

  networking.hostName = "family-server";
  time.timeZone = "Europe/Berlin";
  console.keyMap = "de";
  services.xserver.xkb.layout = "de";

  programs.zsh = {
    enable = true;
    ohMyZsh.enable = true;
  };

  users.users.${server.adminUser} = {
    isNormalUser = true;
    shell = pkgs.zsh;
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
