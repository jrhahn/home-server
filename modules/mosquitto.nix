{ ... }:

{
  # MQTT broker for LAN IoT devices (the rs-smarthome-nodes sensor fleet).
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
          # Restrict the fleet to the topic subtrees it actually uses, rather
          # than the blanket `readwrite #` Home Assistant needs: a node that is
          # ever compromised still cannot reach anything else on the broker.
          #
          # Note that a denial is invisible to the publisher -- mosquitto ACKs a
          # denied QoS-1 publish rather than leaking ACL state -- so a node that
          # is missing a subtree here logs perfectly healthy publishes while the
          # broker discards them. That is exactly how the smarthome/ and
          # homeassistant/ entries below came to be missing until 2026-08-19.
          acl = [
            "readwrite birds/#" # legacy bird-scale topics (hand-declared entities)
            "readwrite smarthome/#" # per-node state + provisioning
            "readwrite homeassistant/#" # MQTT auto-discovery configs
          ];
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

  # The sensor nodes reach the broker over the LAN, so open 1883 there.
  # (Unlike AdGuard, this is intentionally not scoped to tailscale0.)
  networking.firewall.allowedTCPPorts = [ 1883 ];
}
