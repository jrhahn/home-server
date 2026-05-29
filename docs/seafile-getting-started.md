# Seafile Getting Started

Seafile is available only on the private network or through Tailscale:

```text
http://cloud.home.arpa
```

Keep Tailscale connected on phones and laptops before opening Seafile.

## Admin Login

The initial admin email is:

```text
admin@home.arpa
```

The initial admin password is stored on the server in:

```text
/var/lib/secrets/seafile.env
```

Show it with:

```bash
sudo grep '^INIT_SEAFILE_ADMIN_PASSWORD=' /var/lib/secrets/seafile.env
```

Open `http://cloud.home.arpa`, log in with the admin account, then create normal
user accounts from the administration area. Use a normal personal account for
daily sync and keep the admin account for administration.

This setup does not migrate existing Nextcloud data into Seafile. If Nextcloud
was previously enabled on the server, its old state may still exist under
`/srv/nextcloud` until removed manually.

## Phone And Desktop Apps

Install the official Seafile client/app and use this server URL:

```text
http://cloud.home.arpa
```

Log in with the normal user account.

## Access Model

This setup intentionally uses HTTP over private Tailscale/local access:

```nix
enablePublicTls = false;
```

Do not expose the service through router port forwarding. Public HTTPS/ACME
should be reviewed separately before enabling it.

## Maintenance

Seafile runs as Docker containers:

```bash
systemctl status docker-seafile.service
systemctl status docker-seafile-mysql.service
systemctl status docker-seafile-redis.service
```

To watch Seafile logs:

```bash
docker logs seafile -f
```

To create or reset an admin account after setup:

```bash
docker exec -it seafile /opt/seafile/seafile-server-latest/reset-admin.sh
```

## Troubleshooting

If the page does not load, check DNS and the service:

```bash
dig cloud.home.arpa
curl -I http://cloud.home.arpa
systemctl status nginx.service
systemctl status docker-seafile.service
```
