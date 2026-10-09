# GitHub Actions Runner

Self-hosted runners for private GitHub repositories, so their CI does not use
GitHub's paid minutes. Module: [modules/github-runner.nix](../modules/github-runner.nix),
options `server.githubRunner.*` in [modules/options.nix](../modules/options.nix).

## What a job can and cannot do

A job runs code from the repository and from everything the build pulls in
(crates, pub packages, actions, Gradle plugins). One compromised dependency is
enough, so the jobs run in a NixOS container (`gh-runner`, systemd-nspawn):

| | |
|---|---|
| File system | the container's own root; no `/home`, `/srv`, `/var/lib/secrets` or other host state. Only the token directory is bind-mounted, read-only. |
| Network | internet via NAT. Dropped: everything to the host, `10/8`, `172.16/12`, `192.168/16`, `100.64/10` (tailnet), `169.254/16`, multicast, and all IPv6. DNS goes to Quad9, because AdGuard is on the LAN. |
| Inbound | nothing: the runner polls GitHub over outgoing HTTPS, no port is opened. |
| Other repositories | each repository's runner runs as its own user (`gh-<repo>`) with its own `0700` work directory, tool cache and `/tmp`, so a job cannot read another repository's checkout, caches or secrets. |
| Resources | the whole container is capped at `memoryMax` (default 3 GB) and `cpuQuota` (default 2 cores), with low CPU and IO weight, so the family services win. |

Only register **private** repositories. On a public one, a pull request from a
fork could run code here.

## Not for heavy jobs

The J4105 and 8 GB RAM are shared with Immich, Home Assistant and Seafile. Good
fits: Rust tests, `flutter analyze` and `flutter test`, the simulated e2e.
Keep on GitHub-hosted runners: the Android Gradle build (4–6 GB RAM) and
anything needing macOS (iOS).

## Set up

1. **Enable it** in your private `local.nix`:

   ```nix
   server.githubRunner = {
     enable = true;
     # the private repositories with workflows
     repos = [
       "jrhahn/drinklight"
       "jrhahn/ai-trainer-ops"
       "jrhahn/rs-game-jet-ski"
     ];
   };
   ```

2. **Registration tokens**, one per repository, from your laptop (where `gh`
   is logged in). The script asks GitHub for the tokens and writes them on the
   server over SSH (it asks for the sudo password once); it refuses public
   repositories:

   ```bash
   scripts/create-github-runner-tokens.sh admin@family-server \
     jrhahn/drinklight jrhahn/ai-trainer-ops jrhahn/rs-game-jet-ski
   ```

   They are valid for one hour, so do steps 2–3 together. (By hand: the
   repository → *Settings → Actions → Runners → New self-hosted runner*, the
   token from the `--token` line into
   `/var/lib/secrets/github-runner/<owner>-<repo>`, `0600 root`, without a
   trailing newline.)

   Use the registration token, not a personal access token. A PAT would need
   admin rights on the repository, while a registration token can only
   register this runner and expires after an hour.

3. **Deploy:** `nixos-rebuild switch` from your private flake.

4. **Check:**

   ```bash
   sudo nixos-container status gh-runner                  # up
   sudo journalctl -M gh-runner -u github-runner-jrhahn-drinklight -n 50
   ```

   On GitHub, *Settings → Actions → Runners* should show the runner as
   *Idle*, with the labels `self-hosted`, `Linux`, `X64` and `home-nixos`.

5. **Check the jail** (everything except the first must fail or time out):

   ```bash
   sudo nixos-container run gh-runner -- curl -sS -m 5 -o /dev/null -w '%{http_code}\n' https://github.com
   sudo nixos-container run gh-runner -- curl -sS -m 5 http://192.168.1.1     # your router
   sudo nixos-container run gh-runner -- curl -sS -m 5 http://10.231.0.1      # the host
   sudo nixos-container run gh-runner -- curl -sS -m 5 http://100.100.100.100 # tailnet
   sudo nixos-container run gh-runner -- ls /home /srv                        # empty or missing
   ```

## Use it from a repository

Workflows select the runner by its label. drinklight reads the runner from the
repository variable `RUNNER` (*Settings → Secrets and variables → Actions →
Variables*): set it to `home-nixos` to use this runner, and delete it to go
back to GitHub-hosted runners.

```yaml
runs-on: ${{ vars.RUNNER || 'ubuntu-latest' }}
```

Personal GitHub accounts have no account-wide runners (only organizations
do), so each repository gets its own runner and its own variable. Within a
repository, jobs run one after another; jobs of different repositories run
side by side and share the container's memory and CPU caps.

Deploy jobs (e.g. ai-trainer-ops) bring production secrets onto this machine.
The per-repository users keep them away from other repositories' jobs, but a
compromised dependency *in the deploy job itself* sees them, just as it would
on a GitHub-hosted runner.

## Re-registering

As long as the configuration does not change, restarts and reboots reuse the
registration. After changing `repos`, `label` or the token file, the runner
registers again and needs a fresh registration token (step 2; for a new
repository, only that one). An expired
token shows up as HTTP 404 in the configure step of the journal.

## Disk

The container lives under `/var/lib/nixos-containers/gh-runner` on the
internal disk. Expect about 10 GB per repository for the Flutter SDK, Rust
toolchains and build caches. To wipe all caches:

```bash
sudo nixos-container run gh-runner -- sh -c 'rm -rf /var/lib/runner/*/toolcache/*'
sudo systemctl restart container@gh-runner   # work directories are cleaned on start
```
