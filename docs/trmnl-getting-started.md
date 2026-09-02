# TRMNL Getting Started

[TRMNL](https://trmnl.com) is a battery-powered e-paper display that shows a
single full-screen image and sleeps in between. **Terminus** is TRMNL's official
self-hosted server ("BYOS" — bring your own server): the device asks it what to
show, so no screen content ever leaves the house.

It is **off by default**. The admin UI is on the local network or Tailscale:

```text
http://trmnl.home.arpa
```

## How the device talks to the server

The whole protocol is two endpoints:

```text
GET /api/setup     ID: <mac>                        -> api_key, friendly_id
GET /api/display   ID, Access-Token, Refresh-Rate,  -> image_url, refresh_rate,
                   Battery-Voltage, FW-Version, RSSI   update_firmware, ...
```

The device wakes on a timer, fetches a URL, downloads an 800×480 image, draws
it, and goes back to sleep. Everything else — layout, data sources, fonts — is
the server's business. Terminus renders screens with headless Chromium, so a
screen is ultimately just an HTML page.

This matters for one setting. Terminus builds the `image_url` it hands out from
`server.trmnl.apiUri`, so that value must be reachable **from the device**. A
TRMNL is not on the tailnet and cannot route the Tailscale address the other
services in this repo use, so use the server's LAN IP:

```nix
server.trmnl.apiUri = "http://192.168.1.10:2300";
```

A hostname works only if the DNS server handed out by your DHCP resolves it to
the LAN address. When in doubt, use the IP — a wrong `apiUri` fails silently,
with the device fetching nothing and the display staying on its last screen.

## Enable It

1. Generate the secrets on the server (`APP_SECRET`, the PostgreSQL password,
   and the matching connection URLs):

   ```bash
   ./scripts/create-trmnl-secrets.sh
   ```

2. Turn it on in your private `local.nix`:

   ```nix
   server.trmnl = {
     enable = true;
     apiUri = "http://192.168.1.10:2300";  # your server's LAN IP
   };
   ```

3. Apply the config:

   ```bash
   sudo nixos-rebuild switch --flake <your-private-config>#family-server
   ```

   The first start pulls four images, initialises PostgreSQL, and runs the
   database migrations, so give it a couple of minutes:

   ```bash
   systemctl status podman-trmnl-web
   journalctl -fu podman-trmnl-web
   ```

4. Open `http://trmnl.home.arpa` and click **Register**. Registration is open,
   so create your account before pointing any device at the server.

## Connecting a device

A new device — or one reflashed with TRMNL firmware — comes up as an open WiFi
access point named `TRMNL-XXXXXX`, where the suffix is the last three bytes of
its MAC address.

1. Join that network with a phone or laptop.
2. Open `http://4.3.2.1`.
3. Enter your **2.4 GHz** WiFi credentials. 5 GHz is not supported.
4. Expand the custom server field and enter the same value as `apiUri`, e.g.
   `http://192.168.1.10:2300`. Leaving it empty points the device at
   `https://trmnl.app` instead.
5. Save. The device reboots, calls `/api/setup`, and appears under **Devices**
   in Terminus.

The server URL is stored on the device (as the `api_url` preference), so
changing `apiUri` later means running the captive portal again.

## Flashing the firmware

Seeed's TRMNL 7.5" OG DIY Kit ships with Seeed's **factory test firmware**, not
TRMNL firmware: it runs a self-test and stops, leaving the display blank. The
board is a XIAO ESP32-**S3**; the prebuilt binaries in Seeed's firmware repo are
built for the ESP32-**C3** and will not boot on it.

The images that do work are listed by TRMNL's flasher API under the
`seeed_OG_DIY_Kit` key:

```bash
curl -s https://trmnl.com/api/firmware/flash \
  | python3 -c 'import sys,json;print(json.dumps([m for m in json.load(sys.stdin)["data"]["models"] if m["keyname"]=="seeed_OG_DIY_Kit"],indent=2))'
```

They are merged images — bootloader, partition table, and app in one file — so
they are written at offset `0x0`. Back the old contents up first; it is the only
copy of the factory firmware you will get:

```bash
esptool -p /dev/ttyACM0 -b 921600 read-flash 0x0 0x1000000 factory-backup.bin
esptool -p /dev/ttyACM0 -b 921600 erase-flash
esptool -p /dev/ttyACM0 -b 921600 write-flash 0x0 FW1.8.10.bin
esptool -p /dev/ttyACM0 -b 921600 verify-flash 0x0 FW1.8.10.bin
```

`E (…) SPIFFS: mount failed` on the first boot after an erase is expected. If
the display stays blank while the device is otherwise alive (it broadcasts its
access point), check the FPC ribbon cable: the metal side must face **up**.

## Backups

`/srv/trmnl` is included in the `family-local` and `family-hetzner` Borg jobs.
The PostgreSQL cluster is excluded from the file-level backup and dumped instead
by `dump-family-service-databases.service`, which writes `terminus.sql` next to
the Seafile and Immich dumps.

## Upgrades

`server.trmnl.imageTag` defaults to `latest`, and the web container applies
database migrations every time it starts. A NixOS rollback does not undo those.
Pin the tag before an upgrade you care about, and take a dump first:

```bash
sudo systemctl start dump-family-service-databases.service
```
