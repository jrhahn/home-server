{ ... }:

{
  # A time server for the LAN, which exists for exactly one client: the
  # rs-smarthome-nodes sensor fleet.
  #
  # An ESP32-C3 has no clock that survives losing power, so a node does not know
  # the year until something tells it. Its readings used to be dated by whoever
  # received them, which is correct while the archiver is listening and wrong
  # the moment it is not -- a value the broker held back would land with the
  # time of its delivery rather than of its measurement. The firmware now asks
  # for the time once per publish round (`src/ntp.rs` over there) and stamps
  # each reading with when its sensor actually produced it.
  #
  # NixOS's default is systemd-timesyncd, which is an SNTP *client*: it keeps
  # this machine's own clock right and answers nobody. Nothing was listening on
  # UDP/123 at all, so the nodes would have asked into the void and silently
  # published unstamped for ever -- the failure mode being a feature that
  # appears to work while doing nothing. Enabling chrony replaces timesyncd
  # (NixOS turns it off itself), so this machine keeps its clock the same way it
  # did and gains the ability to hand it out.
  services.chrony = {
    enable = true;

    # Serve the LAN, and only the LAN. chrony denies every client by default,
    # which is the right default for something that answers unauthenticated
    # UDP -- the nodes are on the wired/Wi-Fi subnet, and nothing off it has
    # business asking this machine what time it is.
    extraConfig = ''
      allow 192.168.1.0/24
    '';
  };

  # Like mosquitto's 1883, and deliberately not scoped to tailscale0: the sensor
  # nodes join over Wi-Fi on the LAN and are not on the tailnet.
  networking.firewall.allowedUDPPorts = [ 123 ];
}
