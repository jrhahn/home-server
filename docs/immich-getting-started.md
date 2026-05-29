# Immich Getting Started

Immich is available only on the private network or through Tailscale:

```text
http://photos.home.arpa
```

Keep Tailscale connected on phones and laptops before opening Immich.

## First Login

Open `http://photos.home.arpa` in a browser. The first account created in the
Immich web UI becomes the admin account.

After creating the admin account, additional users can be managed from:

```text
Administration -> Users
```

## Phone App

Install the Immich mobile app and use this server URL:

```text
http://photos.home.arpa
```

Log in with the Immich user account created in the web UI. Enable automatic
backup in the app for the albums that should be uploaded.

## Recommended First Settings

Leave Google Cast disabled unless Chromecast support is needed. It loads
external Google resources.

Enable the storage template engine if the on-disk photo library should be
human-readable. Originals are stored under `/srv/immich-originals`, which is
intended to become the future HDD mount. A simple date-based template is:

```text
{{y}}/{{y}}-{{MM}}-{{dd}}/{{filename}}
```

Do not casually change the storage template after uploads have started. Immich
owns the library layout; use Immich for normal file management.

## Storage Layout

The layout is prepared for a future separate drive:

```text
SSD/current system disk:
  /srv/immich                generated files and service data
  /srv/immich/thumbs         thumbnails
  /srv/immich/encoded-video  transcoded video
  /srv/immich/profile        profile images
  /srv/immich/backups        Immich app backup folder
  /srv/immich/tmp            upload/process temp
  /srv/immich/ml-cache       machine-learning cache
  PostgreSQL and Redis       managed by NixOS

Future HDD:
  /srv/immich-originals      original uploaded photos/videos
```

When adding the HDD later, stop Immich, copy `/srv/immich-originals` to the new
drive, mount the drive at `/srv/immich-originals`, then start Immich again.

## Troubleshooting

If the page does not load, check DNS and the service:

```bash
dig photos.home.arpa
curl -I http://photos.home.arpa
systemctl status immich-server.service
systemctl status immich-machine-learning.service
```

If the browser reports a dynamically imported module/chunk error, clear site
data for `photos.home.arpa` or test in a private browser window.
