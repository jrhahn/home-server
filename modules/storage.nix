{ server, ... }:

{
  systemd.tmpfiles.rules = [
    "d /srv 0755 root root -"
    "d /srv/home-assistant 0750 hass hass -"
    "d /srv/nextcloud 0750 nextcloud nextcloud -"
    "d /srv/immich 0750 immich immich -"
    "d /srv/backups 0750 root root -"
    "d /srv/backups/database-dumps 0750 root root -"
  ];

  networking.hosts.${server.tailscaleAddress} = [
    server.cloudDomain
    server.homeAssistantDomain
    server.photosDomain
  ];
}
