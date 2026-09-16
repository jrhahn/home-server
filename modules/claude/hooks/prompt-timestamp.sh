#!/usr/bin/env bash
# UserPromptSubmit hook: stamps every prompt of yours with a HH:MM:SS clock line.
#
# Claude Code renders a hook's `systemMessage` in the transcript right below the
# submitted prompt. Returning JSON (instead of bare stdout) keeps the timestamp
# out of the model's context - it is display-only.
#
# The hook payload arrives on stdin and must be drained, otherwise the writer
# can see EPIPE.
cat >/dev/null 2>&1
printf '{"systemMessage":"%s"}\n' "$(date '+%H:%M:%S')"
exit 0
