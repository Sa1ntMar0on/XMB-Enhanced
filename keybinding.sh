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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Single source of truth: the marker text and the bound id both come from
# manifest.json, so renaming the id can never leave this script behind.
PLUGIN_ID="$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SCRIPT_DIR/manifest.json" | head -1)"
[[ -n $PLUGIN_ID ]] || { echo "keybinding.sh: cannot read id from manifest.json" >&2; exit 1; }
BEGIN="-- BEGIN $PLUGIN_ID SUPER+SPACE takeover (auto-managed)"
END="-- END $PLUGIN_ID SUPER+SPACE takeover (auto-managed)"
# Single-quoted so every backslash and quote survives verbatim; __ID__ is
# substituted below. Keeps the Lua escaping identical to the original literal.
BIND_LINE='o.bind("SUPER + SPACE", "XMB menu", "out=$(omarchy-shell shell call __ID__ ping '"'"'{}'"'"' 2>/dev/null); [ \"$out\" = ok ] && omarchy-shell shell toggle __ID__ '"'"'{\"menu\":\"root\"}'"'"' || omarchy-menu toggle root")'
BIND_LINE="${BIND_LINE//__ID__/$PLUGIN_ID}"

verb="${1-take}"
[[ -f $BINDINGS ]] || touch "$BINDINGS"

strip_block() {
  # Match the marker shape, not the literal id. Renaming the plugin id would
  # otherwise orphan a block written by the previous id, leaving two SUPER+SPACE
  # bindings stacked with the dead one first.
  local tmp
  tmp=$(mktemp)
  awk '
    /-- BEGIN io\.github\..* SUPER\+SPACE takeover \(auto-managed\)/ { skip = 1; next }
    /-- END io\.github\..* SUPER\+SPACE takeover \(auto-managed\)/   { skip = 0; next }
    skip == 0 { print }
  ' "$BINDINGS" > "$tmp"
  cat "$tmp" > "$BINDINGS"
  rm -f "$tmp"
}

has_block() {
  grep -qE -- '-- BEGIN io\.github\..* SUPER\+SPACE takeover \(auto-managed\)' "$BINDINGS"
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
    if has_block; then
      strip_block
    fi
    ;;

  take)
    # Already present and unchanged: leave the file alone so a Hyprland
    # reload is not triggered on every shell start. Matches on the marker
    # shape and the bound id, so a rename still replaces the old block.
    if has_block && grep -qF -e "toggle $PLUGIN_ID" "$BINDINGS"; then
      exit 0
    fi
    strip_block
    ensure_trailing_newline
cat > "$BINDINGS.tmp.$$" <<EOF
$BEGIN
hl.unbind("SUPER + SPACE")
$BIND_LINE
$END
EOF
cat "$BINDINGS.tmp.$$" >> "$BINDINGS"
rm -f "$BINDINGS.tmp.$$"
    ;;

  *)
    echo "usage: keybinding.sh [take|release]" >&2
    exit 1
    ;;
esac

exit 0