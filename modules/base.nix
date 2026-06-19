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

  environment.systemPackages = with pkgs; [
    borgbackup
    btop
    pkgsUnstable.codex
    cvTexLive
    dua
    duf
    fd
    curl
    dig
    file
    gh
    git
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
    psmisc
    python3
    ripgrep
    rsync
    smartmontools
    tmux
    tree
    usbutils
    vim
    wget
  ];
}
