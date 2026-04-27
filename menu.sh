# ==============================================================================
# menu.sh - FZF-Powered Interactive Menu Selection Library
# ==============================================================================
# A reusable library for creating interactive menus using fzf.
# Source this file to use menu_select() in your scripts.
#
# Features:
#   - FZF-powered fuzzy selection
#   - Customizable prompts and height
#   - Sets MENU_INDEX to selected item's index (0-based)
#   - Supports items from arguments or stdin
#
# Usage:
#   source ./menu.sh
#
#   # Pass items as args (recommended)
#   choice="$(menu_select -p 'Pick a thing > ' Alpha Beta Gamma)"
#   echo "Picked: $choice (index $MENU_INDEX)"
#
#   # Or read items from stdin
#   choice="$(printf '%s\n' one two three | menu_select --prompt 'Choose > ')" || echo "Cancelled"
#
# Related scripts:
#   - select_device.sh: Uses menu.sh to select block devices
#   - mountPartition.sh: Uses menu.sh to select partition labels
#   - clonezilla_backup_to_drive.sh: Uses menu.sh for backup/restore options
#
# Env (fallbacks, optional):
#   MENU_PROMPT="Select > "   # used if --prompt not given
#   MENU_HEIGHT=15            # used if --height not given
# ==============================================================================

menu_select() {
  # Require fzf
  if ! command -v fzf >/dev/null 2>&1; then
    echo "menu_select: fzf is required. Install it, e.g.:" >&2
    echo "  sudo apt update && sudo apt install -y fzf" >&2
    return 127
  fi

  # -------- options --------
  local prompt="${MENU_PROMPT:-Select > }"
  local height="${MENU_HEIGHT:-}"
  while (( $# )); do
    case "$1" in
      -p|--prompt)
        [[ $# -ge 2 ]] || { echo "menu_select: --prompt requires an argument" >&2; return 2; }
        prompt="$2"; shift 2;;
      -H|--height)
        [[ $# -ge 2 ]] || { echo "menu_select: --height requires an argument" >&2; return 2; }
        height="$2"; shift 2;;
      --) shift; break;;
      -h|--help)
        cat >&2 <<'USAGE'
menu_select [-p PROMPT] [-H HEIGHT] [--] [ITEM ...]
If no ITEMs are provided, reads newline-separated items from stdin.
Prints the selected item to stdout and sets MENU_INDEX (0-based).
Returns 0 on success; non-zero (e.g. 130) on cancel.
USAGE
        return 2;;
      *)
        break;;
    esac
  done

  # -------- collect items --------
  local -a items=()
  if (( $# )); then
    items=("$@")
  else
    mapfile -t items || return 1
  fi
  ((${#items[@]})) || { echo "menu_select: no items to choose from" >&2; return 1; }

  # -------- invoke fzf --------
  local -a fzf_opts=(--reverse --prompt="$prompt")
  [[ -n "$height" ]] && fzf_opts+=(--height "$height")

  local choice
  choice="$(printf '%s\n' "${items[@]}" | fzf "${fzf_opts[@]}")" || return $?  # propagate cancel

  # -------- compute index --------
  MENU_INDEX=
  local i
  for i in "${!items[@]}"; do
    [[ "${items[$i]}" == "$choice" ]] && MENU_INDEX=$i && break
  done

  printf '%s\n' "$choice"
  return 0
}
