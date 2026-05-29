{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.server;
in
{
  # Defaults can be overridden from your private config (local.nix).
  networking.hostName = lib.mkDefault "family-server";
  time.timeZone = lib.mkDefault "Europe/Berlin";
  console.keyMap = lib.mkDefault "de";
  services.xserver.xkb.layout = lib.mkDefault "de";

  zramSwap = {
    enable = true;
    memoryPercent = 100;
    priority = 100;
  };

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

  users.users.${cfg.adminUser} = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "docker"
    ];
    openssh.authorizedKeys.keys = cfg.adminSshKeys;
  };

  security.sudo.wheelNeedsPassword = true;

  system.stateVersion = "25.11";
}
