#!/bin/bash
# Runs each variant of gtk/app.py on a macOS runner and records what GTK's macOS backend puts into the macOS menu bar:
# the menus and their items as System Events reports them (VARIANT-menus.txt), a screenshot with the application in
# front (VARIANT-screen.png), and one with the menu of the application's name open (VARIANT-appmenu.png).
#
# Usage: gtk/run.sh OUT

set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-out}
mkdir -p "$OUT"

log() {
  echo "$(date +%T) $*" | tee -a "$OUT/log.txt"
}

log "macOS $(sw_vers -productVersion)"
brew install gtk4 libadwaita pygobject3 > "$OUT/brew.txt" 2>&1 || log "brew install failed, see brew.txt"
log "$(brew list --versions gtk4 libadwaita pygobject3 | tr '\n' ' ')"

# The Python for which Homebrew built PyGObject.
PY=
for candidate in "$(brew --prefix)"/bin/python3 "$(brew --prefix)"/opt/python@3*/bin/python3; do
  if "$candidate" -c 'import gi' 2> /dev/null; then
    PY=$candidate
    break
  fi
done
log "python ${PY:-none found}"
[ -n "$PY" ] || exit 1

for variant in menubar primary adw; do
  log "== $variant"
  "$PY" "$HERE/app.py" "$variant" > "$OUT/$variant-app.log" 2>&1 &
  pid=$!
  sleep 10
  osascript "$HERE/menus.applescript" "$pid" > "$OUT/$variant-menus.txt" 2>&1
  cat "$OUT/$variant-menus.txt" | tee -a "$OUT/log.txt"
  screencapture -x "$OUT/$variant-screen.png"
  # The menu of the application's name is the second item of the menu bar, after the Apple menu.
  osascript -e "tell application \"System Events\" to tell (first application process whose unix id is $pid) to click menu bar item 2 of menu bar 1" \
    >> "$OUT/log.txt" 2>&1
  sleep 1
  screencapture -x "$OUT/$variant-appmenu.png"
  osascript -e 'tell application "System Events" to key code 53' >> "$OUT/log.txt" 2>&1
  sleep 1
  kill "$pid" 2> /dev/null
  wait "$pid" 2> /dev/null
done
