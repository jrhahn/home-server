{ pkgs, ... }:

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

  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@example.invalid";
  };

  environment.systemPackages = with pkgs; [
    borgbackup
    btop
    dua
    duf
    fd
    curl
    dig
    file
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
    openssl
    pciutils
    psmisc
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
