{
  config,
  lib,
  server,
  ...
}:

let
  cfg = server.smarthomeTimeseries;
  # Where QuestDB listens, declared once by the module that starts it. Three
  # things have to agree on this -- its own config file, the archiver, and the
  # backup's checkpoint -- so none of them spells it out a second time.
  questdb = config.services.smarthome-timeseries.questdb.httpEndpoint;
in
lib.mkIf cfg.enable {
  # The service itself, its schema and its QuestDB come from the fleet's own
  # repository (`nixosModules.smarthome-timeseries`, imported in flake.nix).
  # What belongs here is only the wiring into this house: which broker, which
  # credentials, which name it answers to.
  services.smarthome-timeseries = {
    enable = true;

    settings = {
      mqtt = {
        # The broker is on this machine, so loopback -- the fleet reaches it
        # over the LAN, but this does not have to.
        host = "127.0.0.1";
        port = 1883;
        # Its own user rather than the fleet's `birdscale`: the archiver only
        # ever reads, and a subscriber that cannot publish cannot corrupt the
        # topics it is archiving. See modules/mosquitto.nix.
        user = "archiver";
        client_id = "smarthome-timeseries";
      };

      questdb = {
        url = "http://${questdb}";
        retention = cfg.retention;
        # Every commit fans out into a refresh of the rollup views, so this is
        # the knob that sets steady-state database load. The fleet publishes
        # about eighteen readings a minute; five seconds is unnoticeable on a
        # chart and keeps the write amplification down.
        flush_interval_secs = 5;
      };

      web.bind = "127.0.0.1:${toString cfg.port}";
    };

    # Handed to the unit as a systemd credential, so it never reaches the Nix
    # store. The same file mosquitto hashes for the `archiver` user.
    mqtt.passwordFile = "/var/lib/secrets/mosquitto-archiver-password";
  };

  services.nginx.virtualHosts.${server.timeseriesDomain} = {
    enableACME = server.enablePublicTls;
    forceSSL = server.enablePublicTls;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString cfg.port}";
      recommendedProxySettings = true;
    };
  };
}

# Nothing opens a firewall port here, deliberately. QuestDB's HTTP interface
# serves ingestion, arbitrary SQL *and* a web console without authenticating any
# of it, so it stays on loopback: the archiver reaches it there, and so does
# anyone who wants the console, over an SSH tunnel.
