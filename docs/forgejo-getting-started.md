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

The runner advertises `ubuntu-latest`, `ubuntu-24.04` and `ubuntu-22.04`,
mapped to catthehacker's act images (pinned by digest in `modules/forgejo.nix`).
Workflows resolve `uses: actions/checkout@v4`
against `github.com` (`DEFAULT_ACTIONS_URL = "github"`), so the runner needs
outbound internet for those steps.

Check the runner registered:

```bash
systemctl status gitea-runner-default.service
journalctl -u gitea-runner-default.service --since '10 min ago'
```

Rerun the token script only to rotate the token, then restart the runner.

#### Boards for hardware tests

A board on the server's USB gets a runner of its own, so only the jobs that ask
for it see it:

```nix
server.forgejo.actions.deviceRunners.esp32c3-bench = "AC:27:6E:7E:5F:7C";
```

The value is the USB serial number of the board's serial port (`udevadm info
/dev/ttyACM0 | grep ID_SERIAL_SHORT`). Jobs with `runs-on: esp32c3-bench` run
on `gitea-runner-esp32c3\x2dbench.service` and find the board at
`/dev/ttyACM0`. Its token is the same file as the default runner's. While the
board is unplugged, these jobs fail to start their container; other jobs are
not affected.

### Claude review bot

[`forgejo-claude-review.yml`](forgejo-claude-review.yml) reviews PRs with
inline comments and answers `@claude` mentions from the repo owner, in the
conversation, inline threads and reviews. Asked for code changes, it commits
them to the PR branch (or to `claude/issue-<n>` with a new PR). Copy it to
`.forgejo/workflows/claude.yml` in a repo and add the repo secrets
`CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`) and `REVIEW_TOKEN` (a
Forgejo token with `write:repository` and `write:issue`, ideally of a bot user).

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
