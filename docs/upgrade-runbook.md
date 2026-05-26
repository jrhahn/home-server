# Upgrade Runbook

Use small, observable upgrades for stateful services.

1. Confirm backups exist:

   ```bash
   sudo systemctl start dump-family-service-databases.service
   sudo borg create --stats /srv/backups/borg-local::manual-$(date -u +%Y%m%dT%H%M%SZ) /srv/nextcloud /srv/immich /srv/backups/database-dumps
   ```

2. Update the flake lock:

   ```bash
   nix flake update
   ```

3. Build before switching:

   ```bash
   sudo nixos-rebuild build --flake .#family-server
   ```

4. Switch:

   ```bash
   sudo nixos-rebuild switch --flake .#family-server
   ```

5. Check services:

   ```bash
   systemctl status nextcloud-setup.service nextcloud-cron.service immich-server.service
   journalctl -u nextcloud-setup.service -u immich-server.service --since '30 min ago'
   ```

6. If the host config is bad, roll back:

   ```bash
   sudo nixos-rebuild switch --rollback
   ```

Rollbacks do not roll back app databases. Restore the matching database dump and
data backup if an application migration itself went wrong.
