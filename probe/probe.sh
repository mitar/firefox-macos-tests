#!/usr/bin/env bash
#
# Records what a hosted macOS runner allows for the tests, into OUT_DIR: each step's output in a file of its own and a
# screenshot after it. A step which fails does not stop the others.
#
# Usage: probe.sh OUT_DIR

set -uo pipefail

OUT=$1
mkdir -p "$OUT"
n=0

step() {
  local name=$1
  shift
  n=$((n + 1))
  local file
  file=$(printf '%s/%02d-%s' "$OUT" "$n" "$name")
  echo "== $name"
  "$@" > "$file.txt" 2>&1
  echo "exit $?" >> "$file.txt"
  cat "$file.txt"
  screencapture -x "$file.png" 2>> "$file.txt" || true
}

system() {
  sw_vers
  uname -a
  csrutil status
  system_profiler SPDisplaysDataType | grep -E "Resolution|Display Type|Main Display|Online"
  defaults read -g NSQuitAlwaysKeepsWindows
  defaults read com.apple.loginwindow TALLogoutSavesState
  id
}

apps() {
  ls /Applications
  for app in Firefox "Firefox Nightly" "Google Chrome" "Microsoft Edge" Safari; do
    plist="/Applications/$app.app/Contents/Info.plist"
    [ -f "$plist" ] && echo "$app: $(defaults read "$plist" CFBundleShortVersionString)"
  done
  ls /System/Applications | grep -E "TextEdit|Safari"
  ls /System/Volumes/Preboot/Cryptexes/App/System/Applications 2>/dev/null
  command -v brew
}

tcc() {
  for db in "$HOME/Library/Application Support/com.apple.TCC/TCC.db" /Library/Application\ Support/com.apple.TCC/TCC.db; do
    echo "== $db"
    sudo sqlite3 "$db" "select service, client, auth_value from access" 2>&1 | grep -iE "accessibility|appleevents|screencapture|postevent|bash|osascript|sshd|provisioner|Terminal" | head -40
  done
}

spaces() {
  defaults read com.apple.spaces 2>&1 | grep -E "ManagedSpaceID|\"uuid\"|type =" | head -40
  # The keyboard shortcuts of Mission Control which are on (enabled = 1), by their numbers: 79 and 81 move to the
  # Space on the left and right, 118 to 121 switch to Desktop 1 to 4.
  defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>&1 | grep -A3 -E "^ +(79|81|118|119|120|121) =" | grep -E "=|enabled"
}

add_space() {
  # Mission Control shows the Spaces bar, whose button adds a Space, as Hammerspoon's hs.spaces.addSpaceToScreen does.
  open -a "Mission Control"
  sleep 2
  osascript -e 'tell application "System Events" to tell process "Dock" to get entire contents of group 2 of group 1 of group 1' 2>&1 | head -c 3000
  echo
  osascript -e 'tell application "System Events" to tell process "Dock" to click button 1 of group 2 of group 1 of group 1'
  sleep 2
  key_code 53
  sleep 1
  spaces
}

key_code() {
  osascript -e "tell application \"System Events\" to key code $1 ${2:+using $2}"
}

switch_space() {
  # Control + right arrow moves to the Space on the right.
  key_code 124 "control down"
  sleep 2
  defaults read com.apple.spaces 2>&1 | grep -A2 "Current Space" | head -10
}

dock() {
  osascript -e 'tell application "System Events" to tell process "Dock" to get {name, position, size} of every UI element of list 1'
}

dock_click_firefox() {
  brew install cliclick > /dev/null 2>&1 || true
  local position
  position=$(osascript -e 'tell application "System Events" to tell process "Dock" to get position of UI element "Firefox" of list 1' 2>&1)
  echo "Firefox in the Dock at $position"
  if [[ $position =~ ^([0-9]+),\ ([0-9]+)$ ]]; then
    cliclick "c:$((BASH_REMATCH[1] + 10)),$((BASH_REMATCH[2] + 10))"
    sleep 15
    osascript -e 'tell application "System Events" to get name of every process whose frontmost is true'
    osascript -e 'tell application "System Events" to tell process "firefox" to get name of every window'
  fi
}

step system system
step apps apps
step tcc tcc
step spaces spaces
step add-space add_space
step switch-space switch_space
step dock dock
step dock-click-firefox dock_click_firefox
exit 0
