#!/usr/bin/env bash
# XMB ribbon settings: on/off, animation speed, and scale.
#
#   ribbon.sh                      print everything as KEY=VALUE lines
#   ribbon.sh toggle               flip the ribbon on/off
#   ribbon.sh on | off             set visibility explicitly
#   ribbon.sh speed <value>        set animation speed (seconds of wave per second)
#   ribbon.sh speed + | -          step the speed up or down
#   ribbon.sh speed                print the current speed
#   ribbon.sh scale <value>        set ribbon scale (0.4 - 1.6)
#   ribbon.sh scale + | -          step the scale up or down
#   ribbon.sh scale                print the current scale
#   ribbon.sh reset                restore defaults
#
# The menu rows run this directly instead of going through
# `omarchy-shell shell call ...`, which only reaches a plugin while its Loader
# happens to be mounted — so a menu row would silently do nothing while the
# menu is closed, which is exactly when it needs to work. A file-backed flag
# has no such dependency, and Xmb.qml re-reads it every time the menu opens.
#
# Values are stored one per file as plain tokens, so the QML side can read them
# with `cat` and no parsing.

set -euo pipefail

DIR="${XMB_RIBBON_STATE_DIR:-$HOME/.local/state/omarchy/xmb-ribbon}"
VISIBILITY_FILE="$DIR/visible"
SPEED_FILE="$DIR/speed"
SCALE_FILE="$DIR/scale"

# Defaults match XmbRibbon.qml.
DEF_VISIBILITY="on"
DEF_SPEED="1.0"
DEF_SCALE="0.80"

# Bounds for the step controls.
SPEED_MIN="0.2"
SPEED_MAX="3.0"
SPEED_STEP="0.2"
SCALE_MIN="0.4"
SCALE_MAX="1.6"
SCALE_STEP="0.1"

mkdir -p "$DIR"

read_file() {
  # $1 = file, $2 = default
  [[ -f $1 ]] || { echo "$2"; return; }
  local v
  v="$(tr -d '[:space:]' < "$1")"
  [[ -n $v ]] || { echo "$2"; return; }
  echo "$v"
}

write_file() {
  printf '%s' "$2" > "$1"
}

clamp() {
  # $1 = value, $2 = min, $3 = max. Uses awk for float comparison.
  awk -v v="$1" -v lo="$2" -v hi="$3" 'BEGIN{
    if (v < lo) v = lo; if (v > hi) v = hi; printf "%.2f", v
  }'
}

visibility() { read_file "$VISIBILITY_FILE" "$DEF_VISIBILITY"; }

set_visibility() {
  # `toggle` takes no argument; only on/off do.
  case "$1" in
    on|off) write_file "$VISIBILITY_FILE" "$1" ;;
    toggle)
      if [[ $(visibility) == on ]]; then write_file "$VISIBILITY_FILE" "off"
      else write_file "$VISIBILITY_FILE" "on"; fi
      ;;
    *) echo "usage: ribbon.sh [toggle|on|off]" >&2; exit 1 ;;
  esac
  visibility
}

speed() { read_file "$SPEED_FILE" "$DEF_SPEED"; }

is_number() {
  # awk coerces non-numeric strings to 0, so `v+0 == v+0` is true for "abc"
  # too. Match the string against a number pattern instead.
  [[ $1 =~ ^-?[0-9]+(\.[0-9]+)?$ ]]
}

set_speed() {
  local v
  case "$1" in
    +) v="$(awk -v c="$(speed)" -v s="$SPEED_STEP" 'BEGIN{print c+s}')" ;;
    -) v="$(awk -v c="$(speed)" -v s="$SPEED_STEP" 'BEGIN{print c-s}')" ;;
    *)  v="$1" ;;
  esac
  # Reject non-numeric input rather than writing junk into the state file.
  if ! is_number "$v"; then
    echo "ribbon.sh: speed must be a number, got '$1'" >&2
    exit 1
  fi
  write_file "$SPEED_FILE" "$(clamp "$v" "$SPEED_MIN" "$SPEED_MAX")"
  speed
}

scale() { read_file "$SCALE_FILE" "$DEF_SCALE"; }

set_scale() {
  local v
  case "$1" in
    +) v="$(awk -v c="$(scale)" -v s="$SCALE_STEP" 'BEGIN{print c+s}')" ;;
    -) v="$(awk -v c="$(scale)" -v s="$SCALE_STEP" 'BEGIN{print c-s}')" ;;
    *)  v="$1" ;;
  esac
  if ! is_number "$v"; then
    echo "ribbon.sh: scale must be a number, got '$1'" >&2
    exit 1
  fi
  write_file "$SCALE_FILE" "$(clamp "$v" "$SCALE_MIN" "$SCALE_MAX")"
  scale
}

reset() {
  rm -f "$VISIBILITY_FILE" "$SPEED_FILE" "$SCALE_FILE"
  print_all
}

print_all() {
  echo "visible=$(visibility)"
  echo "speed=$(speed)"
  echo "scale=$(scale)"
}

case "${1-}" in
  "")            print_all ;;
  toggle|on|off) set_visibility "$1" ;;
  speed)         [[ $# -ge 2 ]] && set_speed "$2" || speed ;;
  scale)         [[ $# -ge 2 ]] && set_scale "$2" || scale ;;
  reset)         reset ;;
  *)
    echo "usage: ribbon.sh [toggle|on|off|speed [+-]<v>|scale [+-]<v>|reset]" >&2
    exit 1
    ;;
esac