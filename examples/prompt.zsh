# wt prompt fragment — adds [PARKED] indicator when cwd is under a canonical repo path.
# Source from .zshrc:  [[ -f ~/.config/wt/prompt.zsh ]] && source ~/.config/wt/prompt.zsh

WT_CACHE="${WT_CACHE:-$HOME/.config/wt/paths.cache}"
[[ -r "$WT_CACHE" ]] && source "$WT_CACHE"

_wt_park_indicator() {
  emulate -L zsh
  [[ -z "${WT_CANONICAL_PATHS:-}" ]] && return
  local rp
  rp=$(realpath "$PWD" 2>/dev/null) || rp="$PWD"
  local p
  for p in "${WT_CANONICAL_PATHS[@]}"; do
    if [[ "$rp" == "$p" || "$rp" == "$p"/* ]]; then
      print -P '%F{red}[PARKED]%f '
      return
    fi
  done
}

# Hook into prompt
if [[ -z "${WT_PROMPT_INSTALLED:-}" ]]; then
  PROMPT='$(_wt_park_indicator)'$PROMPT
  WT_PROMPT_INSTALLED=1
fi
