#!/usr/bin/env bash
# XMB apps fallback: enumerate desktop entries the way the omarchy launcher
# does. Row format: label \t value \t current \t icon
#   value  .desktop id (used for gtk-launch and uninstall)
#   icon   themed icon name (empty string when the entry has none)
#
# Filtering mirrors AppLibrary:
#   - NoDisplay/Hidden/OnlyShowIn/NotShowIn via the shell's hidden-entries.sh
#   - the curated omarchy launcher.hides junk list
#   - entries whose Type is present and is not Application
# User entries (XDG_DATA_HOME) win over system ones; first id seen wins.

set -euo pipefail

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

desktop=""
for v in "$XDG_CURRENT_DESKTOP" "$XDG_SESSION_DESKTOP" "$DESKTOP_SESSION"; do
  [[ -n $v ]] && desktop="${desktop:+$desktop:}$v"
done

declare -A seen
declare -A hidden

while IFS= read -r id; do
  id=${id%$'\r'}
  id=${id%.desktop}
  [[ -n $id ]] && hidden[$id]=1
done < <(bash "$OMARCHY_PATH/shell/services/hidden-entries.sh" "$desktop" 2>/dev/null)

if [[ -f $OMARCHY_PATH/default/omarchy/launcher.hides ]]; then
  while IFS= read -r id; do
    id=${id%$'\r'}
    id=${id%.desktop}
    [[ -n $id ]] && hidden[$id]=1
  done < "$OMARCHY_PATH/default/omarchy/launcher.hides"
fi

emit() {
  local dir="$1" file="$2" rel id name icon type
  rel=${file#"$dir"/}
  id=${rel%.desktop}
  id=${id//\//-}
  [[ -n ${seen[$id]:-} ]] && return 0
  [[ -n ${hidden[$id]:-} ]] && return 0
  type=$(sed -n 's/^Type=//p' "$file" | head -n 1)
  [[ $type && $type != Application ]] && return 0
  name=$(sed -n 's/^Name=//p' "$file" | head -n 1)
  [[ -z $name ]] && return 0
  icon=$(sed -n 's/^Icon=//p' "$file" | head -n 1)
  seen[$id]=1
  printf '%s\t%s\t\t%s\n' "$name" "$id" "$icon"
}

scan_dir() {
  local dir="$1" file
  [[ -d $dir ]] || return 0
  while IFS= read -r -d '' file; do
    emit "$dir" "$file"
  done < <(find "$dir" -type f -name '*.desktop' -print0 2>/dev/null | sort -z)
}

scan_dir "${XDG_DATA_HOME:-$HOME/.local/share}/applications"

IFS=":" read -ra data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for data_dir in "${data_dirs[@]}"; do
  scan_dir "$data_dir/applications"
done

scan_dir "$HOME/.local/share/flatpak/exports/share/applications"
scan_dir /var/lib/flatpak/exports/share/applications
scan_dir "$HOME/.nix-profile/share/applications"

exit 0