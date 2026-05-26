# Home Server

NixOS configuration for a family server on an Intel J4105-class machine.

This setup uses native NixOS services for:

- Nextcloud
- Immich
- PostgreSQL and Redis as managed dependencies
- nginx reverse proxy
- database dumps and local Borg backups

Docker is enabled only as an escape hatch for future services without a good
NixOS module.

## First Install

1. Install NixOS 25.11 on the server.
2. Copy the generated hardware config into this repo:

   ```bash
   sudo nixos-generate-config --show-hardware-config > hosts/family-server/hardware-configuration.nix
   ```

3. Edit [hosts/family-server/default.nix](hosts/family-server/default.nix) and set:

   - `cloudDomain`
   - `photosDomain`
   - `enablePublicTls`
   - the SSH public key for `admin`

4. Create the Nextcloud admin password:

   ```bash
   sudo install -d -m 0750 -o root -g root /var/lib/secrets
   sudo sh -c 'openssl rand -base64 32 > /var/lib/secrets/nextcloud-admin-pass'
   sudo chmod 0400 /var/lib/secrets/nextcloud-admin-pass
   ```

5. Build and switch:

   ```bash
   sudo nixos-rebuild switch --flake .#family-server
   ```

6. Initialize the local Borg repo once:

   ```bash
   sudo borg init --encryption=none /srv/backups/borg-local
   ```

## Services

Default local hostnames:

- Nextcloud: `http://cloud.home.arpa`
- Immich: `http://photos.home.arpa`

For public HTTPS, point real DNS names at the server, update the two domain
values, set `enablePublicTls = true`, and replace the ACME email in
[modules/base.nix](modules/base.nix).

## Notes

NixOS rollback protects the host configuration. It does not automatically roll
back Nextcloud or Immich database migrations. Always take a database dump and a
data backup before major upgrades.
