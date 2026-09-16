#!/usr/bin/env bash
# Claude Code statusLine: footer in EVERY Claude session.
# Left : this session (repo + state). Right: global view of all parallel
# sessions (counts + which repos are waiting for you).
#
# Reads the statusLine JSON payload on stdin. Reads shared state files written
# by session-status.sh for the global picture.

input="$(cat 2>/dev/null)"

cwd="$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
model="$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"

repo="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
if [ -n "$repo" ]; then repo="$(basename "$repo")"; else repo="$(basename "$cwd")"; fi

# git branch (empty if not a repo); detached HEAD -> short sha
branch="$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null)"
[ -z "$branch" ] && branch="$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)"

# Colors
R=$'\033[0m'; DIM=$'\033[90m'; RED=$'\033[91m'; YEL=$'\033[93m'; GRN=$'\033[92m'; CYA=$'\033[96m'; SEP=$'\033[90m│\033[0m'

dir="${XDG_RUNTIME_DIR:-/tmp}/claude-sessions"
now="$(date +%s 2>/dev/null || echo 0)"
maxage=$((8*3600))

my_state="idle"; n_wait=0; n_work=0; n_idle=0
waiting_repos=""
if [ -d "$dir" ]; then
  for f in "$dir"/*; do
    [ -e "$f" ] || continue
    IFS=$'\t' read -r st rp cw ts < "$f" 2>/dev/null
    [ -z "$st" ] && continue
    [ -n "$ts" ] && [ "$now" -gt 0 ] && [ $((now - ts)) -gt "$maxage" ] && continue
    case "$st" in
      waiting) n_wait=$((n_wait+1)); waiting_repos="$waiting_repos $rp" ;;
      working) n_work=$((n_work+1)) ;;
      idle)    n_idle=$((n_idle+1)) ;;
    esac
    [ "$(basename "$f")" = "$sid" ] && my_state="$st"
  done
fi

# --- left: this session ---
case "$my_state" in
  working) here="${YEL}⚙ ${repo}${R}" ;;
  waiting) here="${RED}❗${repo}${R}" ;;
  *)       here="${GRN}✓ ${repo}${R}" ;;
esac
[ -n "$branch" ] && here="$here ${CYA}⎇ ${branch}${R}"
[ -n "$model" ] && here="$here ${DIM}${model}${R}"

# --- right: global ---
g="${DIM}alle:${R}"
[ "$n_wait" -gt 0 ] && g="$g ${RED}❗${n_wait}${R}" || g="$g ${DIM}❗0${R}"
[ "$n_work" -gt 0 ] && g="$g ${YEL}⚙${n_work}${R}"
[ "$n_idle" -gt 0 ] && g="$g ${DIM}✓${n_idle}${R}"

# waiting repo names (dedup, drop this repo, cap at 4)
if [ "$n_wait" -gt 0 ]; then
  names="$(printf '%s\n' $waiting_repos | awk '!seen[$0]++' | head -5)"
  shown="$(printf '%s' "$names" | head -4 | paste -sd ',' -)"
  extra=$(( $(printf '%s\n' "$names" | grep -c .) - 4 ))
  [ "$extra" -gt 0 ] && shown="$shown +$extra"
  [ -n "$shown" ] && g="$g ${DIM}→${R} ${RED}${shown}${R}"
fi

printf '%s %s %s' "$here" "$SEP" "$g"
