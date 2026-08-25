# Forgejo Getting Started

Forgejo is the private Git host. It is available only on the local network or
through Tailscale:

```text
http://git.home.arpa
```

Keep Tailscale connected on phones and laptops before opening Forgejo.

## First Admin Account

Registration is disabled (`DISABLE_REGISTRATION = true`) and signed-out viewing
is blocked (`REQUIRE_SIGNIN_VIEW = true`), so there is no public sign-up. Create
the initial admin account once on the server after the first `nixos-rebuild
switch`:

```bash
sudo -u forgejo forgejo \
  --config /srv/forgejo/custom/conf/app.ini \
  --work-path /srv/forgejo \
  admin user create --admin \
    --username admin \
    --email admin@example.invalid \
    --password 'change-me'
```

Log in at `http://git.home.arpa` with that account and change the password.
Create further users from `Site Administration -> Identity & Access -> Users`.

## Creating Repositories

Once logged in, use the `+` menu to create a repository. LFS is enabled, so
large binary assets work out of the box. To push over SSH, add your SSH public
key under `Settings -> SSH / GPG Keys`; the SSH remote uses the normal port 22:

```bash
git remote add origin git@git.home.arpa:youruser/yourrepo.git
git push -u origin main
```

## Actions (CI) — opt-in

Forgejo Actions runs GitHub-style workflows on a local runner backed by Podman.
It is **off by default**. To enable it:

1. Turn it on in your private `local.nix`:

   ```nix
   server.forgejo.actions.enable = true;
   ```

2. Apply the config so Forgejo exposes Actions and the runner service exists:

   ```bash
   sudo nixos-rebuild switch --flake <your-private-config>#family-server
   ```

3. Generate a runner registration token and write it to the file the runner
   expects (`/var/lib/secrets/forgejo-runner-token`):

   ```bash
   <home-server-checkout>/scripts/create-forgejo-runner-token.sh
   ```

4. Restart the runner so it registers (or rebuild again):

   ```bash
   sudo systemctl restart gitea-runner-default.service
   ```

The runner advertises `ubuntu-latest` and `ubuntu-22.04` labels, both mapped to
`node:20-bookworm` containers. Workflows resolve `uses: actions/checkout@v4`
against `github.com` (`DEFAULT_ACTIONS_URL = "github"`), so the runner needs
outbound internet for those steps.

Check the runner registered:

```bash
systemctl status gitea-runner-default.service
journalctl -u gitea-runner-default.service --since '10 min ago'
```

Rerun the token script only to rotate the token, then restart the runner.

## Backups

Forgejo writes its own dump to `/srv/forgejo/dump` at 03:30, and `/srv/forgejo`
is included in the `family-local` Borg job. See the backups section in the
[README](../README.md).

## Troubleshooting

If the page does not load, check DNS and the service:

```bash
dig git.home.arpa
curl -I http://git.home.arpa
systemctl status forgejo.service
```

Official docs: <https://forgejo.org/docs/latest/>
