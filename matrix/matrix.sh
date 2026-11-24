#!/usr/bin/env bash
#
# Runs one scenario of the launch matrix on a hosted macOS runner, for Mozilla bug 2090730. See README.md.
#
# Usage: matrix.sh APP SCENARIO OUT_DIR
#
# APP is firefox (BUILD names the release, such as 161.0 or 162.0b1, installed from archive.mozilla.org). SCENARIO is
# one of A, B1, B2, C, D1, D2, E and F. Every scenario starts with four Spaces, each with a window of another
# application titled "Other N", which tells the Spaces apart, and with the browser's three windows, each with a page of
# its own, on Spaces 1 to 3, saved or open. The user is on Space 4 when the scenario launches the browser with a click
# on its Dock icon, opens a link from another application or crashes it, and on Space 1 when it restarts. OUT_DIR
# receives result.json with the windows on screen, the frontmost application and window before and after and each
# change in between, the windows of each Space at the end, and screenshots.

set -uo pipefail

APP=$1
SCENARIO=$2
OUT=$(mkdir -p "$3" && cd "$3" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
BUILD=${BUILD:-161.0}
PORT=8000

log() { echo "$(date +%T) $*" | tee -a "$OUT/log.txt" >&2; }

# The windows on screen, which are those of the current Space, as a JSON list of [application, title].
onscreen() {
  osascript -l JavaScript -e 'ObjC.import("CoreGraphics");
    var list = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements, 0)));
    JSON.stringify(list.filter(w => w.kCGWindowLayer == 0).map(w => [w.kCGWindowOwnerName, w.kCGWindowName || ""]))'
}

# The number of the current Space: that of the window "Other N" on screen.
current_space() {
  onscreen | python3 -c 'import json,sys,re; print(next((int(t[6:]) for _, t in json.load(sys.stdin) if re.fullmatch(r"Other \d", t)), 0))'
}

key_code() {
  osascript -e "tell application \"System Events\" to key code $1 ${2:+using $2}"
}

keystroke() {
  osascript -e "tell application \"System Events\" to keystroke \"$1\" ${2:+using $2}"
}

type_text() {
  osascript -e "tell application \"System Events\" to keystroke \"$1\""
}

# Switches to Space N with Control+arrow, as the user does, one Space at a time.
space_to() {
  local target=$1 current tries=0
  while current=$(current_space); [ "$current" != "$target" ] && [ $tries -lt 10 ]; do
    if [ "$current" = 0 ] || [ "$current" -gt "$target" ]; then key_code 123 "control down"; else key_code 124 "control down"; fi
    sleep 1.5
    tries=$((tries + 1))
  done
  [ "$(current_space)" = "$target" ] || log "could not switch to Space $target"
}

frontmost() {
  osascript -e 'tell application "System Events"
    set p to first process whose frontmost is true
    set t to ""
    try
      set t to name of front window of p
    end try
    return (name of p) & "|" & t
  end tell' 2>/dev/null
}

snapshot() {
  python3 - "$(current_space)" "$(onscreen)" "$(frontmost)" <<'END'
import json, sys
app, _, window = sys.argv[3].partition("|")
print(json.dumps({"space": int(sys.argv[1]), "onscreen": json.loads(sys.argv[2]), "frontmost": app, "front_window": window}))
END
}

# Records the state every half second until nothing changed for 6 seconds, at least MIN and at most 60 seconds.
observe() {
  local min=$1 start last="" now changed state
  start=$(date +%s)
  changed=$start
  echo "[" > "$OUT/timeline.json"
  local first=1
  while true; do
    now=$(date +%s)
    state=$(snapshot)
    if [ "$state" != "$last" ]; then
      [ $first = 1 ] || echo "," >> "$OUT/timeline.json"
      first=0
      echo "{\"t\": $((now - start)), \"state\": $state}" >> "$OUT/timeline.json"
      last=$state
      changed=$now
    fi
    if [ $((now - start)) -ge 60 ] || { [ $((now - start)) -ge "$min" ] && [ $((now - changed)) -ge 6 ]; }; then
      break
    fi
    sleep 0.5
  done
  echo "]" >> "$OUT/timeline.json"
  echo "$state" > "$OUT/after.json"
  screencapture -x "$OUT/after.png"
}

# The windows of each Space, visited from the first to the last, once the scenario's result is recorded.
spaces() {
  local n
  space_to 1
  echo "{" > "$OUT/spaces.json"
  for n in 1 2 3 4; do
    space_to "$n"
    sleep 1
    echo "\"$n\": $(onscreen)$([ $n -lt 4 ] && echo ,)" >> "$OUT/spaces.json"
    screencapture -x "$OUT/space-$n.png"
  done
  echo "}" >> "$OUT/spaces.json"
}

dock_click() {
  local name=$1 position
  position=$(osascript -e "tell application \"System Events\" to tell process \"Dock\" to get position of UI element \"$name\" of list 1")
  [[ $position =~ ^([0-9]+),\ ([0-9]+)$ ]] || { log "no Dock icon of $name: $position"; return 1; }
  cliclick "c:$((BASH_REMATCH[1] + 20)),$((BASH_REMATCH[2] + 20))"
  # The pointer leaves the Dock, as switching Spaces with the keyboard does nothing while the Dock shows a tooltip.
  sleep 0.5
  cliclick "m:512,300"
}

app_windows() {
  onscreen | python3 -c 'import json,sys; print(sum(1 for a, t in json.load(sys.stdin) if a == "Firefox"))'
}

wait_for_title() {
  local title=$1 i
  for i in $(seq 60); do
    onscreen | grep -q "$title" && return 0
    sleep 0.5
  done
  return 1
}

load() {
  keystroke l "command down"
  sleep 1
  type_text "$1"
  key_code 36
}

setup() {
  log "setup"
  brew install cliclick > /dev/null 2>&1
  defaults write -g NSQuitAlwaysKeepsWindows -bool true
  # Firefox from Mozilla's disk image, with the matrix's policies.
  curl -sSL -o /tmp/firefox.dmg "https://archive.mozilla.org/pub/firefox/releases/$BUILD/mac/en-US/Firefox%20$BUILD.dmg"
  hdiutil attach -quiet -nobrowse -mountpoint /tmp/firefox-dmg /tmp/firefox.dmg
  sudo rm -rf /Applications/Firefox.app
  sudo cp -R /tmp/firefox-dmg/Firefox.app /Applications/
  hdiutil detach -quiet /tmp/firefox-dmg
  sudo xattr -dr com.apple.quarantine /Applications/Firefox.app
  sudo mkdir -p /Applications/Firefox.app/Contents/Resources/distribution
  local policies=firefox-policies.json
  [ "$SCENARIO" = B2 ] || [ "$SCENARIO" = D2 ] && policies=firefox-policies-new-window.json
  sudo cp "$HERE/$policies" /Applications/Firefox.app/Contents/Resources/distribution/policies.json
  log "Firefox $(defaults read /Applications/Firefox.app/Contents/Info.plist CFBundleShortVersionString)"
  # The browser is in the Dock, which has only Apple's applications on a runner.
  defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>/Applications/Firefox.app</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
  killall Dock
  sleep 5
  # The pages, served on localhost.
  mkdir -p /tmp/pages
  for name in page-one page-two page-three url-page; do
    printf '<!DOCTYPE html><title>%s</title><p>%s</p>\n' "$name" "$name" > "/tmp/pages/$name.html"
  done
  (cd /tmp/pages && python3 -m http.server "$PORT" --bind 127.0.0.1 > /dev/null 2>&1 &)
  # Firefox becomes the default browser, which macOS asks the user to confirm.
  osascript -l JavaScript -e 'ObjC.import("CoreServices"); $.LSSetDefaultHandlerForURLScheme($("http"), $("org.mozilla.firefox")); $.LSSetDefaultHandlerForURLScheme($("https"), $("org.mozilla.firefox"))'
  sleep 3
  osascript -e 'tell application "System Events" to tell process "CoreServicesUIAgent"
      repeat with b in (buttons of window 1)
        if name of b starts with "Use" then click b
      end repeat
    end tell' 2>&1 | tee -a "$OUT/log.txt"
  sleep 2
  # Four Spaces, each with a window of another application.
  local i
  for i in 1 2 3; do
    open -a "Mission Control"
    sleep 2
    osascript -e 'tell application "System Events" to tell process "Dock" to click button 1 of group 2 of group 1 of group 1'
    sleep 2
    key_code 53
    sleep 1
  done
  for i in 1 2 3 4; do
    [ $i -gt 1 ] && { key_code 124 "control down"; sleep 2; }
    "$PYTHON" "$HERE/other-app.py" "Other $i" > /dev/null 2>&1 &
    wait_for_title "Other $i" || log "no window Other $i"
    sleep 1
  done
  space_to 1
}

# Opens Firefox's three windows, the first from the Dock on Space 1, the others with its command line on Spaces 2 and 3.
open_windows() {
  space_to 1
  dock_click Firefox
  wait_for_title "Firefox" || log "Firefox opened no window"
  sleep 4
  load "http://localhost:$PORT/page-one.html"
  wait_for_title page-one || log "no window shows page-one"
  local n
  for n in 2 3; do
    space_to $n
    local name
    name=$([ $n = 2 ] && echo page-two || echo page-three)
    /Applications/Firefox.app/Contents/MacOS/firefox -new-window "http://localhost:$PORT/$name.html" > /dev/null 2>&1 &
    wait_for_title "$name" || log "no window shows $name"
    sleep 2
  done
}

quit_firefox() {
  osascript -e 'tell application "System Events" to set frontmost of process "firefox" to true'
  sleep 1
  keystroke q "command down"
  local i
  for i in $(seq 30); do
    pgrep -x firefox > /dev/null || return 0
    sleep 1
  done
  log "Firefox did not quit"
}

main() {
  PYTHON=$(for p in /Library/Frameworks/Python.framework/Versions/3.1*/bin/python3 /usr/bin/python3 python3; do "$p" -c "import tkinter" 2>/dev/null && echo "$p" && break; done)
  log "python with tkinter: $PYTHON"
  setup
  log "seed"
  open_windows
  sleep 16
  case "$SCENARIO" in
    A|B1|B2) quit_firefox ;;
    E) sleep 15; pkill -9 -x firefox; sleep 3 ;;
  esac
  if [ "$SCENARIO" = F ]; then
    space_to 1
    osascript -e 'tell application "System Events" to set frontmost of process "firefox" to true'
    keystroke j "command down, shift down"
    sleep 4
    type_text 'Services.wm.getMostRecentWindow(\"navigator:browser\").setTimeout(() => Services.startup.quit(Ci.nsIAppStartup.eAttemptQuit | Ci.nsIAppStartup.eRestart), 12000)'
    key_code 36
    sleep 1
    keystroke j "command down, shift down"
    sleep 2
  else
    space_to 4
    sleep 8
  fi
  if [[ $SCENARIO == B* || $SCENARIO == D* ]]; then
    "$PYTHON" "$HERE/other-app.py" "Link App" "http://localhost:$PORT/url-page.html" > /dev/null 2>&1 &
    wait_for_title "Link App" || log "no window Link App"
    sleep 2
  fi
  snapshot > "$OUT/before.json"
  screencapture -x "$OUT/before.png"
  log "trigger"
  case "$SCENARIO" in
    A|C|E) dock_click Firefox ;;
    B1|B2|D1|D2) key_code 36 ;;
  esac
  observe $([ "$SCENARIO" = F ] && echo 20 || echo 10)
  spaces
  python3 - "$OUT" "$APP" "$SCENARIO" "$BUILD" <<'END'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
result = {"desktop": "macos", "app": sys.argv[2], "scenario": sys.argv[3], "build": sys.argv[4]}
for name in ("before", "after", "timeline", "spaces"):
    path = out / f"{name}.json"
    result[name] = json.loads(path.read_text()) if path.exists() else None
(out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
END
  log "done"
}

main
