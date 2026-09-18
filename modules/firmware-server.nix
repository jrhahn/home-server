{
  lib,
  server,
  ...
}:

let
  cfg = server.firmwareServer;
in
lib.mkIf cfg.enable {
  # Somewhere for the sensor fleet to fetch firmware images from.
  #
  # The nodes update themselves over the air: a retained MQTT message names a
  # version, a URL and a SHA-256, and the node fetches the image and writes it
  # into whichever of its two application slots it is not currently running from
  # (`docs/ota.md` in rs-smarthome-nodes). MQTT carries the decision; it
  # deliberately does not carry the 750 KB, which would mean writing a chunk
  # protocol that HTTP already is, and leaving an image retained on the broker
  # to be re-delivered to every subscriber on every connect.
  #
  # The first update, on 2026-09-17, was served off a laptop with
  # `python3 -m http.server`, which worked and is not a place to keep firmware:
  # it needs a hole in that laptop's firewall, it is only up while someone is
  # sitting there, and it cannot answer a `Range` request. This is the same job
  # done by the machine that is already always on and already runs nginx.
  #
  # **Plain HTTP, deliberately.** The nodes have no TLS stack — 400 KB of SRAM,
  # and a certificate chain is not where it should go — and the image is checked
  # by digest rather than by transport: an offer names a SHA-256, and a node
  # that fetches anything else refuses it before the selector is touched. The
  # URL is reachable on the LAN only, and anyone who can publish to
  # `smarthome/#` can already provision a board into another room.
  services.nginx.virtualHosts.${cfg.domain} = {
    # The fleet has no DNS: the broker and the time server are baked into the
    # firmware as dotted quads, deliberately, so that a reading's timestamp does
    # not depend on name resolution. A node therefore addresses this machine by
    # IP and sends that IP as its `Host`, which matches nothing unless the
    # address is listed here as well as the name.
    serverAliases = cfg.addresses;

    # Never redirected to HTTPS, whatever the rest of this server does: the
    # firmware follows no redirects — by design, a 301 to somewhere unexpected
    # is not something a node should chase — so a redirect here would read as
    # "server refused the request" on the node and as nothing at all here.
    enableACME = false;
    forceSSL = false;
    addSSL = false;

    locations."/fw/" = {
      alias = "${cfg.root}/";
      extraConfig = ''
        autoindex on;
        # Serving a partially written file as if it were whole is the one way
        # this can hand a node a bad image that still has a plausible length.
        # Images are therefore written elsewhere and moved in, and the digest
        # in the offer is the backstop.
        default_type application/octet-stream;
      '';
    };
  };

  # nginx answers `Range` requests for static files by itself, which is what
  # lets a node resume a download that lost its association instead of starting
  # the 750 KB again. A Python `http.server` ignores the header and answers 200,
  # and the firmware correctly refuses that on a resumed request — so this is
  # not a detail, it is the difference between resume working and never being
  # exercised.
  systemd.tmpfiles.rules = [
    "d ${cfg.root} 0755 ${server.adminUser} users -"
  ];
}
