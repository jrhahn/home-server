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
      # eza with Nerd Font icons; the glyphs are rendered by the SSH client's
      # terminal font (e.g. the laptop's foot + Symbols Nerd Font), so nothing
      # font-related is needed on this headless server. --icons=auto only emits
      # icons to a TTY.
      ls = "eza --group-directories-first --icons=auto";
      ll = "eza -lah --group-directories-first --icons=auto";
      la = "eza -lAh --group-directories-first --icons=auto";
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
