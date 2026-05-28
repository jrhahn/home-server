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
    enableCompletion = true;
    histSize = 10000;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    setOptions = [
      "AUTO_CD"
      "HIST_IGNORE_ALL_DUPS"
      "SHARE_HISTORY"
    ];
    shellAliases = {
      ll = "ls -alF";
      la = "ls -A";
      gs = "git status";
      rebuild = "sudo nixos-rebuild switch --flake ~/home-server#family-server";
    };
    ohMyZsh = {
      enable = true;
      theme = "bira";
      plugins = [
        "colored-man-pages"
        "docker"
        "git"
        "sudo"
        "systemd"
      ];
    };
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
      "ssh-ed25519 AAAA...replace-me... you@example.com"
    ];
  };

  security.sudo.wheelNeedsPassword = true;

  system.stateVersion = "25.11";
}
