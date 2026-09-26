#!/usr/bin/env bash
# XMB SUPER+SPACE keybinding takeover.
#
#   keybinding.sh take     Insert the takeover block into bindings.lua
#   keybinding.sh release  Remove it, restoring the Omarchy menu binding
#
# The block lives at the END of the user's bindings.lua, which Hyprland loads
# after Omarchy's defaults, so hl.unbind() sees the default SUPER+SPACE bind.
# Managed by the plugin lifecycle: written when the plugin loads (also on every
# shell start, idempotently and only when the file actually changes), removed
# when the plugin is disabled or its directory is deleted.
#
# The bound command degrades gracefully: when the plugin is disabled, removed,
# or its component fails to load, the ping check answers "unknown" and the
# stock `omarchy-menu toggle root` runs instead. POSIX-only shell syntax and
# Lua-escaped quotes, so it survives Hyprland's sh -c and the Lua string parse.

set -euo pipefail

BINDINGS="${XMB_BINDINGS_FILE:-$HOME/.config/hypr/bindings.lua}"
BEGIN="-- BEGIN io.github.fab679.xmb SUPER+SPACE takeover (auto-managed)"
END="-- END io.github.fab679.xmb SUPER+SPACE takeover (auto-managed)"
BIND_LINE='o.bind("SUPER + SPACE", "XMB menu", "out=$(omarchy-shell shell call io.github.fab679.xmb ping '"'"'{}'"'"' 2>/dev/null); [ \"$out\" = ok ] && omarchy-shell shell toggle io.github.fab679.xmb '"'"'{\"menu\":\"root\"}'"'"' || omarchy-menu toggle root")'

verb="${1-take}"
[[ -f $BINDINGS ]] || touch "$BINDINGS"

strip_block() {
  local tmp
  tmp=$(mktemp)
  awk -v b="$BEGIN" -v e="$END" '
    index($0, b) { skip = 1; next }
    index($0, e) { skip = 0; next }
    skip == 0 { print }
  ' "$BINDINGS" > "$tmp"
  cat "$tmp" > "$BINDINGS"
  rm -f "$tmp"
}

ensure_trailing_newline() {
  # $(tail -c 1) strips a trailing newline itself, so a file ending in \n
  # yields "" here and the append is correctly skipped.
  [[ -s $BINDINGS ]] || return 0
  [[ -n $(tail -c 1 "$BINDINGS") ]] && echo "" >> "$BINDINGS"
  return 0
}

case "$verb" in
  release)
    if grep -qF -e "$BEGIN" "$BINDINGS"; then
      strip_block
    fi
    ;;

  take)
    # Already present and unchanged: leave the file alone so a Hyprland
    # reload is not triggered on every shell start.
    if grep -qF -e "$BEGIN" "$BINDINGS" && grep -qF -e "toggle io.github.fab679.xmb" "$BINDINGS"; then
      exit 0
    fi
    strip_block
    ensure_trailing_newline
    {
      echo "$BEGIN"
      echo 'hl.unbind("SUPER + SPACE")'
      printf '%s\n' "$BIND_LINE"
      echo "$END"
    } >> "$BINDINGS"
    ;;

  *)
    echo "usage: keybinding.sh [take|release]" >&2
    exit 1
    ;;
esac

exit 0