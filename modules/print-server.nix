# CUPS print server for the USB-attached Brother TD-2020 label printer, shared
# to the LAN and the tailnet and advertised over mDNS so other devices can
# discover and print to it. Driver packaging lives in ./pkgs/brother-td2020.nix.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.server.printServer;
  brother-td2020 = pkgs.callPackage ./pkgs/brother-td2020.nix {
    glibc_i686 = pkgs.pkgsi686Linux.glibc;
  };
in
{
  config = lib.mkIf cfg.enable {
    # Only the Brother filter blob is unfree; allow just that, nothing else.
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "brother-td2020" ];

    services.printing = {
      enable = true;
      drivers = [ brother-td2020 ];

      # Listen on all interfaces and share queues; who may actually reach cupsd
      # is restricted by allowFrom below and the firewall.
      listenAddresses = [ "*:631" ];
      browsing = true;
      defaultShared = true;
      allowFrom = [
        "localhost"
        "192.168.1.0/24" # LAN
        "100.64.0.0/10" # Tailscale (CGNAT range)
      ];
    };

    # The i386 driver binaries hardcode /opt/brother/PTouch/td2020/... paths, so
    # expose the driver tree there. L+ replaces any stale link on activation.
    systemd.tmpfiles.rules = [
      "L+ /opt/brother - - - - ${brother-td2020}/opt/brother"
    ];

    # Declare the printer so the queue exists (and prints) right after a rebuild.
    hardware.printers = {
      ensurePrinters = [
        {
          name = cfg.printerName;
          deviceUri = cfg.deviceUri;
          # PPD resolved by name from the CUPS model dir, which the driver above
          # populates via services.printing.drivers.
          model = "brother_td2020_printer_en.ppd";
          location = config.networking.hostName;
          description = "Brother TD-2020 label printer";
          # The printer can't sense the roll, so pin the label size as the
          # queue default (see server.printServer.mediaSize). Left unset if empty.
          ppdOptions = lib.optionalAttrs (cfg.mediaSize != "") {
            PageSize = cfg.mediaSize;
          };
        }
      ];
      ensureDefaultPrinter = cfg.printerName;
    };

    # Advertise the shared queue via mDNS/Bonjour for zero-config discovery.
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        userServices = true;
      };
      openFirewall = true; # UDP 5353
    };

    # IPP. The host has no public interface (LAN + Tailscale only), and cupsd's
    # allowFrom above is the actual access gate.
    networking.firewall.allowedTCPPorts = [ 631 ];
  };
}
