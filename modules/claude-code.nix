# Claude Code's configuration layer — the hooks, the theme and settings.json.
#
# The binary itself comes from pkgsUnstable.claude-code in base.nix; this is
# everything else under the admin user's ~/.claude, carried over from the
# laptop config repo the same way p10k.zsh is (see modules/system.nix).
#
# ~/.claude is NOT one kind of thing, which is why this module treats its
# contents differently:
#
#   hooks/, themes/  Claude Code only ever reads them, so they become store
#                    symlinks — one per file rather than one per directory, so
#                    the directories stay real and writable. Claude Code
#                    creates caches and state next to these files, and a
#                    directory symlink into the store would make that fail.
#   settings.json    Claude Code WRITES it — the first `/config` change it
#                    stores in user settings (the theme, for one), and `/model`
#                    saving a default. A store symlink is read-only and would
#                    break both, so it is installed as a writable copy instead.
#   .credentials.json,  session token, history and caches. Secrets or state;
#   .claude.json,       neither belongs in a git repo, so neither is touched.
#   projects/, history.jsonl
#
# This host has no home-manager, so it is a plain activation script rather than
# `home.file`. It runs after `users`, which is what creates the home directory.
#
# What is deliberately NOT carried over from the laptop: the `permissions.allow`
# list and the `autoMode` block. Both are full of work-repo paths, internal
# hostnames and org detail, and this repo is public. Standing approvals ("yes,
# and don't ask again") land in a project's .claude/settings.local.json anyway,
# not here, so the block below stays short and reviewable.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.server;
  user = config.users.users.${cfg.adminUser};
  homeDir = user.home;

  # statusLine gets no shell and no tilde expansion, so the absolute path is
  # baked in at build time. That also keeps the file correct for an adminUser
  # other than the default. The hook commands below it are run through a shell
  # and use ~ directly.
  settings = pkgs.replaceVars ./claude/settings.json { inherit homeDir; };

  # `ln -sfn` per file, for the reason in the header. Note the asymmetry: a file
  # dropped from this repo leaves its symlink behind in ~/.claude and has to be
  # removed by hand — the alternative, wiping the directory first, would take
  # Claude Code's own state with it.
  linkInto =
    subdir: source:
    lib.concatMapStringsSep "\n" (name: ''
      ln -sfn ${source}/${name} "${homeDir}/.claude/${subdir}/${name}"
      chown -h ${cfg.adminUser}:${user.group} "${homeDir}/.claude/${subdir}/${name}"
    '') (lib.attrNames (builtins.readDir source));
in
{
  system.activationScripts.claudeCodeConfig = {
    deps = [ "users" ];
    text = ''
      install -d -m 0755 -o ${cfg.adminUser} -g ${user.group} \
        "${homeDir}/.claude" "${homeDir}/.claude/hooks" "${homeDir}/.claude/themes"

      ${linkInto "hooks" ./claude/hooks}
      ${linkInto "themes" ./claude/themes}

      # A copy, not a symlink, so Claude Code can still write to it. The trade:
      # every activation resets the file to what is in this repo, so a theme
      # picked in /config or a model set with /model survives only until the
      # next rebuild. Change those in modules/claude/settings.json instead.
      #
      # The old file is kept once, so a change made in the app is recoverable
      # rather than silently gone.
      claudeSettings="${homeDir}/.claude/settings.json"
      if ! ${pkgs.diffutils}/bin/cmp -s ${settings} "$claudeSettings"; then
        if [ -e "$claudeSettings" ]; then
          cp -- "$claudeSettings" "$claudeSettings.before-home-server"
          chown ${cfg.adminUser}:${user.group} "$claudeSettings.before-home-server"
        fi
        install -m 0644 -o ${cfg.adminUser} -g ${user.group} ${settings} "$claudeSettings"
      fi
    '';
  };
}
