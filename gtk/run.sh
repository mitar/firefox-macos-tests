#!/bin/bash
# Runs a variant of gtk/app.py on a macOS runner and records what GTK's macOS backend puts into the macOS menu bar: the
# menus and their items as System Events reports them (menus.txt), a screenshot right after the start (started.png),
# one with the application in front (screen.png), and one with the menu of the application's name open (appmenu.png).
#
# Usage: gtk/run.sh VARIANT OUT

set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
VARIANT=$1
OUT=${2:-out}
mkdir -p "$OUT"

log() {
  echo "$(date +%T) $*" | tee -a "$OUT/log.txt"
}

log "macOS $(sw_vers -productVersion), variant $VARIANT"
brew install gtk4 libadwaita pygobject3 cliclick > "$OUT/brew.txt" 2>&1 || log "brew install failed, see brew.txt"
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

"$PY" "$HERE/app.py" "$VARIANT" > "$OUT/app.log" 2>&1 &
pid=$!
sleep 10
log "process $(ps -o pid=,stat=,comm= -p "$pid" || echo gone)"
screencapture -x "$OUT/started.png"

# macOS does not let a process started in the background take the focus, so a click on its window, in the middle of the
# screen, where GTK places it, activates the application, as a user does.
window=$(osascript -e "tell application \"System Events\" to tell (first application process whose unix id is $pid) to get {position, size} of window 1" 2>&1)
log "window $window"
if [[ $window =~ ^([0-9]+),\ ([0-9]+),\ ([0-9]+),\ ([0-9]+)$ ]]; then
  cliclick "c:$((BASH_REMATCH[1] + BASH_REMATCH[3] / 2)),$((BASH_REMATCH[2] + BASH_REMATCH[4] / 2))"
else
  cliclick "c:512,384"
fi
sleep 3
osascript "$HERE/menus.applescript" "$pid" > "$OUT/menus.txt" 2>&1
tee -a "$OUT/log.txt" < "$OUT/menus.txt"
screencapture -x "$OUT/screen.png"

# The menu of the application's name is the second item of the menu bar, after the Apple menu.
osascript -e "tell application \"System Events\" to tell (first application process whose unix id is $pid) to click menu bar item 2 of menu bar 1" \
  >> "$OUT/log.txt" 2>&1
sleep 1
screencapture -x "$OUT/appmenu.png"
osascript -e 'tell application "System Events" to key code 53' >> "$OUT/log.txt" 2>&1

# The application exits with SIGTERM, which is no failure of the run.
kill "$pid" 2> /dev/null
wait "$pid" 2> /dev/null || true
