# Paperless-ngx Getting Started

Paperless-ngx is OCR-based document management. It is **off by default** and,
once enabled, available only on the local network or through Tailscale:

```text
http://paperless.home.arpa
```

Keep Tailscale connected on phones and laptops before opening Paperless.

## Enable It

1. Create the admin password file on the server (plain text, one line, root
   owned and not in the Nix store):

   ```bash
   sudo install -d -m 0750 /var/lib/secrets
   printf '%s\n' 'your-admin-password' \
     | sudo install -m 0600 /dev/stdin /var/lib/secrets/paperless-admin-password
   ```

2. Turn it on in your private `local.nix`. Set the OCR language(s) for your
   documents — language packs install automatically, combine with `+`,
   most-used first:

   ```nix
   server.paperless = {
     enable = true;
     ocrLanguage = "deu+eng";  # default is "eng"
   };
   ```

3. Apply the config:

   ```bash
   sudo nixos-rebuild switch --flake ~/home-server-private#family-server
   ```

## First Login

Open `http://paperless.home.arpa` and log in as `admin` with the password from
`/var/lib/secrets/paperless-admin-password`. Create additional users from the
admin area if needed.

## Adding Documents

Two ways to get documents in:

- **Upload** through the web UI (drag and drop), or the Paperless mobile app
  pointed at `http://paperless.home.arpa`.
- **Consume folder**: drop files into `/srv/paperless/consume` on the server and
  Paperless ingests them automatically:

  ```bash
  sudo cp scan.pdf /srv/paperless/consume/
  ```

Paperless runs OCR, extracts text, and files each document. Use tags,
correspondents, and document types to organize; saved views and full-text
search make retrieval fast.

## Storage and Backups

- Document data lives under `/srv/paperless` (media, archive, index, the
  consume folder). When `server.storage.externalDisk` is enabled, the bulk
  document store is eligible to live on the external disk.
- The PostgreSQL database is created locally and stays on the internal disk.

> **Not yet backed up.** As of now `/srv/paperless` is **not** included in the
> `family-local` Borg job in [modules/maintenance.nix](../modules/maintenance.nix),
> and the Paperless PostgreSQL database is not dumped. Do not treat Paperless as
> the only copy of important scans until you add `/srv/paperless` to the backup
> paths (and a Paperless DB dump). Keep originals elsewhere in the meantime.

## Troubleshooting

If the page does not load, check DNS and the services:

```bash
dig paperless.home.arpa
curl -I http://paperless.home.arpa
systemctl status paperless-web.service
systemctl status paperless-consumer.service
journalctl -u paperless-consumer.service --since '15 min ago'
```

A document stuck in `consume/` usually means the consumer service failed or the
OCR language pack is missing — check the consumer log above.

Official docs: <https://docs.paperless-ngx.com/>
