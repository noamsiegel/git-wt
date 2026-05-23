# wt prompt fragment — adds [PARKED] indicator when cwd is under a canonical repo path.
# Source from .bashrc:  [[ -f ~/.config/wt/prompt.bash ]] && source ~/.config/wt/prompt.bash

WT_CACHE="${WT_CACHE:-$HOME/.config/wt/paths.cache}"
[[ -r "$WT_CACHE" ]] && source "$WT_CACHE"

_wt_park_indicator() {
  [[ -z "${WT_CANONICAL_PATHS:-}" ]] && return
  local rp
  rp=$(realpath "$PWD" 2>/dev/null) || rp="$PWD"
  local p
  for p in "${WT_CANONICAL_PATHS[@]}"; do
    if [[ "$rp" == "$p" || "$rp" == "$p"/* ]]; then
      printf '\001\033[31m\002[PARKED]\001\033[0m\002 '
      return
    fi
  done
}

if [[ -z "${WT_PROMPT_INSTALLED:-}" ]]; then
  PS1='$(_wt_park_indicator)'$PS1
  WT_PROMPT_INSTALLED=1
fi
