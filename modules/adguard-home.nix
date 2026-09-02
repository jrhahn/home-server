{
  config,
  lib,
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
        rewrites = [
          {
            domain = server.adguardDomain;
            answer = server.tailscaleAddress;
          }
          {
            domain = server.cloudDomain;
            answer = server.tailscaleAddress;
          }
          {
            domain = server.gitDomain;
            answer = server.tailscaleAddress;
          }
          {
            domain = server.homeAssistantDomain;
            answer = server.tailscaleAddress;
          }
          {
            domain = server.photosDomain;
            answer = server.tailscaleAddress;
          }
        ]
        # Admin UI only. The e-paper device is not on the tailnet and reaches
        # Terminus over the LAN via server.trmnl.apiUri instead.
        ++ lib.optional server.trmnl.enable {
          domain = server.trmnlDomain;
          answer = server.tailscaleAddress;
        };
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
