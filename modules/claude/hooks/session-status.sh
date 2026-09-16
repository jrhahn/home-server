#!/usr/bin/env bash
# Claude Code parallel-session awareness for Sway + foot.
# Usage (from settings.json hooks): session-status.sh <state>
#   state: working | waiting | idle | end
#
# Does two things, both best-effort (never fails the hook, always exits 0):
#   1) Marks the owning Sway window `urgent` when Claude is WAITING for you
#      (permission/input), clears it otherwise. Works even if the window is
#      unfocused / on another workspace. No titlebars required.
#   2) Writes a per-session state file so `claude-sessions` can give a global
#      overview (e.g. a Waybar module).
#
# Claude Code sets its own foot window title (repo/task + spinner) — we do NOT
# touch the title, so its richer title stays intact.

state="${1:-idle}"
input="$(cat 2>/dev/null)"

cwd="$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"
[ -z "$session_id" ] && session_id="unknown"

repo="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
if [ -n "$repo" ]; then repo="$(basename "$repo")"; else repo="$(basename "$cwd")"; fi

# --- 1) Sway urgency on the owning foot window -------------------------------
find_term_pid() {
  local pid=$PPID name ppid
  for _ in $(seq 1 20); do
    [ "$pid" -le 1 ] && break
    name=$(awk '$1=="Name:"{print $2; exit}' /proc/$pid/status 2>/dev/null)
    [ "$name" = "foot" ] && { echo "$pid"; return 0; }
    ppid=$(awk '$1=="PPid:"{print $2; exit}' /proc/$pid/status 2>/dev/null)
    pid=$ppid
  done
  return 1
}

if command -v swaymsg >/dev/null 2>&1; then
  tp="$(find_term_pid)"
  if [ -n "$tp" ]; then
    con_id="$(swaymsg -t get_tree 2>/dev/null | jq -r --argjson p "$tp" \
      'first(.. | objects | select(.pid? == $p) | .id) // empty' 2>/dev/null)"
    if [ -n "$con_id" ]; then
      case "$state" in
        waiting) swaymsg "[con_id=$con_id] urgent enable"  >/dev/null 2>&1 || true ;;
        *)       swaymsg "[con_id=$con_id] urgent disable" >/dev/null 2>&1 || true ;;
      esac
    fi
  fi
fi

# --- 2) Shared state file for the overview -----------------------------------
dir="${XDG_RUNTIME_DIR:-/tmp}/claude-sessions"
mkdir -p "$dir" 2>/dev/null
f="$dir/$session_id"
if [ "$state" = "end" ]; then
  rm -f "$f" 2>/dev/null
else
  printf '%s\t%s\t%s\t%s\n' "$state" "$repo" "$cwd" "$(date +%s)" > "$f" 2>/dev/null
fi

exit 0
