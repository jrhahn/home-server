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
    "d /srv/immich-originals/library 0750 immich immich -"
    "d /srv/immich-originals/upload 0750 immich immich -"
    "L /srv/immich-originals/backups - - - - /srv/immich/backups"
    "L /srv/immich-originals/encoded-video - - - - /srv/immich/encoded-video"
    "L /srv/immich-originals/profile - - - - /srv/immich/profile"
    "L /srv/immich-originals/thumbs - - - - /srv/immich/thumbs"
    "f /srv/immich-originals/backups/.immich 0600 immich immich -"
    "f /srv/immich-originals/encoded-video/.immich 0600 immich immich -"
    "f /srv/immich-originals/library/.immich 0600 immich immich -"
    "f /srv/immich-originals/profile/.immich 0600 immich immich -"
    "f /srv/immich-originals/thumbs/.immich 0600 immich immich -"
    "f /srv/immich-originals/upload/.immich 0600 immich immich -"
    "d /srv/seafile 0750 root root -"
    "d /srv/seafile-mysql 0750 root root -"
    "d /srv/seafile-redis 0770 999 999 -"
    "d /srv/backups 0750 root root -"
    "d /srv/backups/database-dumps 0750 root root -"
  ];

  networking.hosts.${server.tailscaleAddress} = [
    server.cloudDomain
    server.gitDomain
    server.homeAssistantDomain
    server.photosDomain
  ];
}
