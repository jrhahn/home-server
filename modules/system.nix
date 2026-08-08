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
    # promptInit is emitted after interactiveShellInit, which is where the
    # oh-my-zsh module sources oh-my-zsh.sh and loads the theme -- so this is
    # the one hook guaranteed to run once powerlevel10k is actually defined.
    # oh-my-zsh sets promptInit to "" with mkDefault, so overriding it here is
    # not a conflict.
    #
    # p10k.zsh is `p10k configure` output, copied verbatim from the laptop
    # config repo (that is where a wizard can realistically be run; this host
    # is headless). Hand-tuned deltas live in p10k-overrides.zsh so refreshing
    # the generated file cannot silently drop them.
    promptInit = ''
      source ${./p10k/p10k.zsh}
      source ${./p10k/p10k-overrides.zsh}
    '';
    ohMyZsh = {
      enable = true;
      # customPkgs links each package's share/zsh/themes into $ZSH_CUSTOM, so
      # zsh-powerlevel10k lands at themes/powerlevel10k/ -- hence the two-part
      # theme name. The powerline glyphs are rendered by the SSH client's
      # terminal font, so this headless host needs no fonts of its own.
      theme = "powerlevel10k/powerlevel10k";
      customPkgs = [ pkgs.zsh-powerlevel10k ];
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

  # Hard stop: refuse to activate the placeholder reference instance. This runs
  # before the `users` activation script (deps = [ ]), so it aborts the switch
  # *before* the example's placeholder adminSshKeys can overwrite authorized_keys
  # and lock you out. Build/`nix flake check` are unaffected (activation scripts
  # do not run at build time).
  system.activationScripts.refuseReferenceInstance = lib.mkIf cfg.isReferenceInstance {
    deps = [ ];
    text = ''
      echo "FATAL: server.isReferenceInstance = true — this is the placeholder" >&2
      echo "reference config (nixosConfigurations.example), not a real deployment." >&2
      echo "It carries placeholder SSH keys and would lock you out. Refusing to" >&2
      echo "activate. Deploy your private flake (e.g. ~/home-server-private#family-server)." >&2
      exit 1
    '';
  };

  system.stateVersion = "25.11";
}
