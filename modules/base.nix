{ pkgs, ... }:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.firewall.enable = true;

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
    curl
    dig
    git
    htop
    jq
    rsync
    vim
  ];
}
