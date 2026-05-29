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

## Create User Accounts

Log in as `admin@home.arpa`, then open:

```text
Avatar/menu -> System Admin -> Users -> Add User
```

Create one account per person. The email address is the login name. It does not
need to be a public email address unless email delivery is configured later.

This setup does not migrate existing Nextcloud data into Seafile. If Nextcloud
was previously enabled on the server, its old state may still exist under
`/srv/nextcloud` until removed manually.

## Fedora Desktop Client

The easiest daily setup on Fedora is the graphical sync client:

```bash
sudo dnf install seafile-client
```

Start it from the application launcher or with:

```bash
seafile-applet
```

Add an account with:

```text
Server: http://cloud.home.arpa
Email:  your Seafile user email
Password: your Seafile user password
```

When the client asks for a local Seafile folder, choose for example:

```text
~/Seafile
```

Seafile does not automatically create one fixed Dropbox-style folder for
everything. Instead, it syncs individual libraries. In the client, click `Sync`
on a library and choose where it should live locally. A good default is to sync
libraries below `~/Seafile`.

There is no Dropbox-like Nautilus overlay required for basic sync. Synced
libraries are normal local folders; Nautilus can edit them like any other
folder.

## Fedora CLI Client

Use the GUI unless there is a good reason to script syncs. The CLI is useful for
servers, terminals, or debugging.

Install the CLI package if your Fedora install provides it:

```bash
sudo dnf install seafile
```

Initialize and start the CLI client:

```bash
mkdir -p ~/seafile-client ~/Seafile
seaf-cli init -d ~/seafile-client
seaf-cli start
```

List remote libraries. Do not pass `-p`; the CLI will ask for the password
interactively, keeping it out of shell history:

```bash
seaf-cli list-remote -s http://cloud.home.arpa -u your-user@example.local
```

Sync a library by name when the library name is unique:

```bash
seaf-cli download-by-name -n "My Library" -s http://cloud.home.arpa -d ~/Seafile -u your-user@example.local
```

Or sync by library ID. The library ID is visible in the web UI URL after opening
the library:

```bash
seaf-cli download -l library-uuid-here -s http://cloud.home.arpa -d ~/Seafile -u your-user@example.local
```

Useful CLI commands:

```bash
seaf-cli status
seaf-cli list
seaf-cli stop
```

## Phone Apps

Install the official Seafile client/app and use this server URL:

```text
http://cloud.home.arpa
```

Log in with the normal user account.

## Laptop DNS Note

If Fedora says `Could not resolve host: cloud.home.arpa` but the server works,
add the Tailscale address to `/etc/hosts` on the laptop:

```bash
sudo sh -c 'grep -q "cloud.home.arpa" /etc/hosts || printf "\n# home-server over Tailscale\n100.64.0.1 family-server cloud.home.arpa photos.home.arpa ha.home.arpa\n" >> /etc/hosts'
sudo resolvectl flush-caches
```

## Access Model

This setup intentionally uses HTTP over private Tailscale/local access:

```nix
enablePublicTls = false;
```

Do not expose the service through router port forwarding. Public HTTPS/ACME
should be reviewed separately before enabling it.

## Maintenance

Seafile runs as Podman containers:

```bash
systemctl status podman-seafile.service
systemctl status podman-seafile-mysql.service
systemctl status podman-seafile-redis.service
```

To watch Seafile logs:

```bash
podman logs seafile -f
```

To create or reset an admin account after setup:

```bash
podman exec -it seafile /opt/seafile/seafile-server-latest/reset-admin.sh
```

## Troubleshooting

If the page does not load, check DNS and the service:

```bash
dig cloud.home.arpa
curl -I http://cloud.home.arpa
systemctl status nginx.service
systemctl status podman-seafile.service
```

Official docs:

- <https://help.seafile.com/syncing_client/install_linux_client/>
- <https://help.seafile.com/syncing_client/linux-cli/>
