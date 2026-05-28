{ server, ... }:

{
  services.adguardhome = {
    enable = true;
    host = "127.0.0.1";
    port = 3000;
    openFirewall = false;
    mutableSettings = false;

    settings = {
      dns = {
        bind_hosts = [ "0.0.0.0" ];
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
            domain = server.cloudDomain;
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
        ];
      };
    };
  };

  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 ];
  };
}
