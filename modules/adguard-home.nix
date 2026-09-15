{
  config,
  server,
  ...
}:

{
  services.adguardhome = {
    enable = true;
    host = "127.0.0.1";
    port = 3000;
    openFirewall = false;
    mutableSettings = false;

    settings = {
      dns = {
        bind_hosts = [
          "127.0.0.1"
          server.tailscaleAddress
        ];
        port = 53;
        upstream_dns = [
          "https://dns10.quad9.net/dns-query"
          "https://one.one.one.one/dns-query"
        ];
        bootstrap_dns = [
          "9.9.9.10"
          "1.1.1.1"
        ];
      };

      filtering = {
        protection_enabled = true;
        # Every local hostname resolves to this server. The list itself lives in
        # modules/options.nix so /etc/hosts cannot answer for a name this does
        # not. For TRMNL that covers the admin UI only -- the e-paper device is
        # not on the tailnet and reaches Terminus over the LAN via
        # server.trmnl.apiUri instead.
        rewrites = map (domain: {
          inherit domain;
          answer = server.tailscaleAddress;
        }) server.localDomains;
      };
    };
  };

  services.nginx.virtualHosts.${server.adguardDomain} = {
    enableACME = server.enablePublicTls;
    forceSSL = server.enablePublicTls;

    locations."/" = {
      proxyPass = "http://${config.services.adguardhome.host}:${toString config.services.adguardhome.port}";
      recommendedProxySettings = true;
    };
  };

  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 ];
  };
}
