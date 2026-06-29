{ pkgs, pkgsUnstable, ... }:

let
  cvTexLive = pkgs.texlive.combine {
    inherit (pkgs.texlive)
      scheme-small
      moderncv
      fontawesome5
      enumitem
      tools;
  };

  # graphifyy isn't in nixpkgs and pulls ~28 tree-sitter grammar wheels that
  # aren't packaged either, so we expose its `graphify` CLI through a uv-managed
  # isolated environment instead of a full Python derivation.
  graphify = pkgs.writeShellScriptBin "graphify" ''
    exec ${pkgs.uv}/bin/uv tool run --from graphifyy graphify "$@"
  '';
in
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.firewall.enable = true;

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  programs.mosh.enable = true;

  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@example.invalid";
  };

  programs.direnv.enable = true;

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [ stdenv.cc.cc.lib zlib ];
  };

  environment.systemPackages = with pkgs; [
    borgbackup
    btop
    cmake
    gcc
    stdenv.cc.cc.lib
    pkgsUnstable.claude-code
    pkgsUnstable.codex
    cvTexLive
    dua
    duf
    eza
    bat
    fd
    curl
    fzf
    dig
    file
    gh
    git
    graphify
    helix
    htop
    iftop
    inetutils
    iotop
    jq
    lsof
    ncdu
    nix-output-monitor
    pkgsUnstable.corepack
    pkgsUnstable.nodejs
    openssl
    pciutils
    poppler-utils
    zlib
    psmisc
    python3
    ripgrep
    rsync
    smartmontools
    tmux
    tree
    usbutils
    uv
    vim
    wget
  ];
}
