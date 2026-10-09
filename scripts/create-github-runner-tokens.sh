#!/usr/bin/env bash
#
# Fetch a GitHub runner registration token for each repository and install it
# where the gh-runner container expects it (server.githubRunner.tokenDir).
#
# Run it on your laptop, where `gh` is logged in:
#
#   scripts/create-github-runner-tokens.sh admin@family-server jrhahn/drinklight jrhahn/rs-game-jet-ski
#
# The tokens go to a 0700 directory in the admin user's home over SSH, then
# one `ssh -t` moves them into place with sudo (it asks for the sudo password)
# and removes the staging copy. They never touch the laptop's disk.
#
# Registration tokens expire after one hour, so run `nixos-rebuild switch` (or
# restart the container) right after. Rerun only when a runner has to register
# again (changed repos/label, or a fresh container).
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <ssh-host> <owner/repo>..." >&2
  exit 1
fi

host="$1"
shift
dir="/var/lib/secrets/github-runner"
staging=".github-runner-tokens"

# staging is meant to expand here, on the laptop
# shellcheck disable=SC2029
ssh "${host}" "umask 077 && rm -rf ~/${staging} && mkdir ~/${staging}"
for repo in "$@"; do
  if [[ "$(gh repo view "${repo}" --json visibility -q .visibility)" != "PRIVATE" ]]; then
    echo "Skipping ${repo}: only private repositories may use this runner." >&2
    continue
  fi
  name="${repo//\//-}"
  # shellcheck disable=SC2029
  gh api -X POST "repos/${repo}/actions/runners/registration-token" -q .token |
    tr -d '\n' | ssh "${host}" "umask 077 && cat > ~/${staging}/${name}"
  echo "Fetched ${repo}"
done

# shellcheck disable=SC2029
ssh -t "${host}" "sudo install -d -m 0700 -o root -g root '${dir}' \
  && sudo install -m 0600 -o root -g root ~/${staging}/* '${dir}/' \
  ; rm -rf ~/${staging}"
echo "Installed into ${host}:${dir}"
echo "Now, within the hour: nixos-rebuild switch ...  (or: sudo systemctl restart container@gh-runner)"
