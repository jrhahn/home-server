{ ... }:

{
  # MQTT broker for LAN IoT devices (e.g. the rs-bird-scale feeder scale).
  # Home Assistant's `mqtt` integration is only a client; it needs a broker to
  # talk to. This provides one.
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        # IoT devices join over Wi-Fi on the LAN, not Tailscale, so bind on all
        # interfaces and gate access with authentication (below) + the firewall.
        address = "0.0.0.0";
        port = 1883;
        settings.allow_anonymous = false;

        users.birdscale = {
          # Cleartext password read from a file kept OUT of the repo; mosquitto
          # hashes it on load. Create it on the server (matching the firmware's
          # MQTT_PASSWORD in the rs-bird-scale .env):
          #   umask 077
          #   printf '%s' 'your-chosen-password' \
          #     > /var/lib/secrets/mosquitto-birdscale-password
          passwordFile = "/var/lib/secrets/mosquitto-birdscale-password";
          # Restrict the device to its own topic subtree.
          acl = [ "readwrite birds/#" ];
        };

        # Home Assistant connects as a full client (subscribe to everything it
        # is configured for). Create its secret the same way.
        users.homeassistant = {
          passwordFile = "/var/lib/secrets/mosquitto-homeassistant-password";
          acl = [ "readwrite #" ];
        };
      }
    ];
  };

  # The bird scale reaches the broker over the LAN, so open 1883 there.
  # (Unlike AdGuard, this is intentionally not scoped to tailscale0.)
  networking.firewall.allowedTCPPorts = [ 1883 ];
}
