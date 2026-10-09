#!/usr/bin/env bash
#
# Fetch a GitHub runner registration token for each repository and write it
# where the gh-runner container expects it (server.githubRunner.tokenDir).
#
# Run it on your laptop, where `gh` is logged in; the tokens go to the server
# over SSH and never touch the laptop's disk:
#
#   scripts/create-github-runner-tokens.sh admin@family-server jrhahn/drinklight jrhahn/rs-game-jet-ski
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

for repo in "$@"; do
  if [[ "$(gh repo view "${repo}" --json visibility -q .visibility)" != "PRIVATE" ]]; then
    echo "Skipping ${repo}: only private repositories may use this runner." >&2
    continue
  fi
  token="$(gh api -X POST "repos/${repo}/actions/runners/registration-token" -q .token)"
  file="${dir}/${repo//\//-}"
  # dir and file are meant to expand here, on the laptop
  # shellcheck disable=SC2029
  printf '%s' "${token}" | ssh "${host}" \
    "sudo install -d -m 0700 -o root -g root '${dir}' && sudo install -m 0600 -o root -g root /dev/stdin '${file}'"
  echo "Wrote ${host}:${file}"
done

echo "Now, within the hour: sudo nixos-rebuild switch ...  (or: sudo systemctl restart container@gh-runner)"
