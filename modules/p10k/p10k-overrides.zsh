# Deviations from the `p10k configure` output in p10k.zsh.
#
# Kept separate on purpose: p10k.zsh is wizard-generated and is meant to be
# replaceable wholesale (it is copied verbatim from the laptop config repo,
# which is where the wizard actually runs). Anything hand-tuned belongs here
# instead, so refreshing that file never silently drops it. Sourced right after
# p10k.zsh from programs.zsh.promptInit (see modules/system.nix).

# The wizard puts user@hostname in the right prompt and then blanks it for
# local non-root shells via
#   POWERLEVEL9K_CONTEXT_{DEFAULT,SUDO}_{CONTENT,VISUAL_IDENTIFIER}_EXPANSION=
# Over SSH it would still show, but a console or `sudo -i` session would lose
# it. On a box that is administered from several directions, the hostname is
# exactly the thing worth never losing, so drop those overrides and let
# CONTEXT_TEMPLATE ('%n@%m') apply again.
unset POWERLEVEL9K_CONTEXT_DEFAULT_CONTENT_EXPANSION
unset POWERLEVEL9K_CONTEXT_SUDO_CONTENT_EXPANSION
unset POWERLEVEL9K_CONTEXT_DEFAULT_VISUAL_IDENTIFIER_EXPANSION
unset POWERLEVEL9K_CONTEXT_SUDO_VISUAL_IDENTIFIER_EXPANSION

# Move it to the far left, next to the directory, rather than the right edge.
# Filtering the arrays instead of redefining them keeps the wizard's remaining
# segment choices intact when p10k.zsh is refreshed.
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
  ${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS:#context}
)
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
  context
  ${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS:#context}
)

# The wizard selected instant_prompt=verbose, which needs its cache-sourcing
# block at the very top of the rc file. Here the whole prompt is set up from
# /etc/zshrc, where oh-my-zsh sources the theme in interactiveShellInit and
# this file runs later still via promptInit -- nothing that late can make
# instant prompt pay off. Turn it off rather than leave the config claiming a
# feature that never engages.
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off
