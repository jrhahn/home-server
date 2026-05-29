{ server, ... }:

{
  systemd.tmpfiles.rules = [
    "d /srv 0755 root root -"
    "d /srv/home-assistant 0750 hass hass -"
    "d /srv/immich 0750 immich immich -"
    "d /srv/immich/backups 0750 immich immich -"
    "d /srv/immich/encoded-video 0750 immich immich -"
    "d /srv/immich/ml-cache 0750 immich immich -"
    "d /srv/immich/profile 0750 immich immich -"
    "d /srv/immich/thumbs 0750 immich immich -"
    "d /srv/immich/tmp 0750 immich immich -"
    "d /srv/immich-originals 0750 immich immich -"
    "d /srv/seafile 0750 root root -"
    "d /srv/seafile-mysql 0750 root root -"
    "d /srv/seafile-redis 0750 root root -"
    "d /srv/backups 0750 root root -"
    "d /srv/backups/database-dumps 0750 root root -"
  ];

  networking.hosts.${server.tailscaleAddress} = [
    server.cloudDomain
    server.homeAssistantDomain
    server.photosDomain
  ];
}
