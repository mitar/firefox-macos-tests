#!/usr/bin/env bash
#
# Runs one scenario of the launch matrix on a hosted macOS runner, for Mozilla bug 2090730. See README.md.
#
# Usage: matrix.sh APP SCENARIO OUT_DIR
#
# APP is firefox (BUILD names the release, such as 161.0 or 162.0b1, installed from archive.mozilla.org), chrome, edge,
# safari or textedit. SCENARIO is one of A, B1, B2, C, D1, D2, E and F, of which TextEdit has A, C and E, and Safari,
# which has no command to restart, all but F. Every scenario starts with four Spaces, each with a window of another
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

case "$APP" in
  firefox) NAME=Firefox; PROC=firefox; BUNDLE=org.mozilla.firefox; APP_PATH=/Applications/Firefox.app ;;
  chrome) NAME="Google Chrome"; PROC="Google Chrome"; BUNDLE=com.google.Chrome; APP_PATH="/Applications/Google Chrome.app"
    QUIT_URL=chrome://quit; RESTART_URL=chrome://restart ;;
  edge) NAME="Microsoft Edge"; PROC="Microsoft Edge"; BUNDLE=com.microsoft.edgemac; APP_PATH="/Applications/Microsoft Edge.app"
    QUIT_URL=edge://quit; RESTART_URL=edge://restart ;;
  safari) NAME=Safari; PROC=Safari; BUNDLE=com.apple.Safari; APP_PATH=/Applications/Safari.app ;;
  textedit) NAME=TextEdit; PROC=TextEdit; BUNDLE=; APP_PATH=/System/Applications/TextEdit.app ;;
  *) echo "unknown application $APP" >&2; exit 2 ;;
esac

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

# Switches to Space N by clicking it in Mission Control's Spaces bar, as Control+arrow does nothing while some
# applications are frontmost, and with Control+arrow when the click did not reach it.
space_to() {
  local target=$1 current tries=0
  [ "$(current_space)" = "$target" ] && return 0
  # Control+arrow does nothing while Firefox or Safari is frontmost, so Finder comes to the front first.
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  open -a "Mission Control"
  sleep 1.5
  osascript -e "tell application \"System Events\" to tell process \"Dock\" to click button $target of list 1 of group \"Spaces Bar\" of group 1 of group \"Mission Control\"" > /dev/null 2>&1 \
    || key_code 53
  sleep 2
  while current=$(current_space); [ "$current" != "$target" ] && [ $tries -lt 6 ]; do
    if [ "$current" = 0 ] || [ "$current" -gt "$target" ]; then key_code 123 "control down"; else key_code 124 "control down"; fi
    sleep 1.5
    tries=$((tries + 1))
  done
  if [ "$(current_space)" != "$target" ]; then
    log "could not switch to Space $target"
    open -a "Mission Control"
    sleep 1.5
    osascript -e 'tell application "System Events" to tell process "Dock" to get {name, role} of every UI element of list 1 of group "Spaces Bar" of group 1 of group "Mission Control"' >> "$OUT/log.txt" 2>&1
    key_code 53
  fi
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
  onscreen | NAME="$NAME" python3 -c 'import json,os,sys; print(sum(1 for a, t in json.load(sys.stdin) if a == os.environ["NAME"]))'
}

wait_for_app_window() {
  local i
  for i in $(seq 60); do
    [ "$(app_windows)" -gt 0 ] && return 0
    sleep 0.5
  done
  return 1
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

# Loads the page NAME in the frontmost window, again when the window does not show it, as when a page Edge shows at its
# start takes the keys.
load_page() {
  local name=$1 attempt
  for attempt in 1 2 3; do
    load "http://localhost:$PORT/$name.html"
    wait_for_title "$name" && return 0
  done
  return 1
}

setup() {
  log "setup"
  brew install cliclick > /dev/null 2>&1
  defaults write -g NSQuitAlwaysKeepsWindows -bool true
  setup_app
  # The application is in the Dock, which has only Apple's applications on a runner, Safari among them.
  if [ "$APP" != safari ]; then
    defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$APP_PATH</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
    killall Dock
    sleep 5
  fi
  # The pages, served on localhost, and the documents of TextEdit.
  mkdir -p /tmp/pages
  for name in page-one page-two page-three url-page; do
    printf '<!DOCTYPE html><title>%s</title><p>%s</p>\n' "$name" "$name" > "/tmp/pages/$name.html"
    echo "$name" > "/tmp/pages/$name.txt"
  done
  (cd /tmp/pages && python3 -m http.server "$PORT" --bind 127.0.0.1 > /dev/null 2>&1 &)
  # The browser becomes the default browser, which macOS asks the user to confirm.
  if [ -n "$BUNDLE" ] && [ "$APP" != safari ]; then
    osascript -l JavaScript -e "ObjC.import('CoreServices'); \$.LSSetDefaultHandlerForURLScheme(\$('http'), \$('$BUNDLE')); \$.LSSetDefaultHandlerForURLScheme(\$('https'), \$('$BUNDLE'))"
    sleep 3
    osascript -e 'tell application "System Events" to tell process "CoreServicesUIAgent"
        repeat with b in (buttons of window 1)
          if name of b starts with "Use" then click b
        end repeat
      end tell' 2>&1 | tee -a "$OUT/log.txt"
    sleep 2
  fi
  setup_spaces
}

setup_app() {
  case "$APP" in
    firefox) setup_firefox ;;
    chrome|edge)
      local domain support
      domain=$([ "$APP" = chrome ] && echo com.google.Chrome || echo com.microsoft.Edge)
      support=$([ "$APP" = chrome ] && echo "Google/Chrome" || echo "Microsoft Edge")
      sudo xattr -dr com.apple.quarantine "$APP_PATH"
      # Continue where it left off, which is not the default, and none of the questions of a first start.
      defaults write "$domain" RestoreOnStartup -int 1
      defaults write "$domain" DefaultBrowserSettingEnabled -bool false
      defaults write "$domain" PromotionalTabsEnabled -bool false
      defaults write "$domain" MetricsReportingEnabled -bool false
      defaults write "$domain" PrivacySandboxPromptEnabled -bool false
      defaults write "$domain" HideFirstRunExperience -bool true
      defaults write "$domain" DefaultSearchProviderEnabled -bool true
      defaults write "$domain" DefaultSearchProviderName -string Example
      defaults write "$domain" DefaultSearchProviderSearchURL -string 'https://search.example/?q={searchTerms}'
      mkdir -p "$HOME/Library/Application Support/$support"
      touch "$HOME/Library/Application Support/$support/First Run"
      choose_restore "$HOME/Library/Application Support/$support"
      ;;
  esac
  log "$NAME $(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)"
}

# Chooses to continue where the browser left off, as its settings page does: its RestoreOnStartup policy applies on
# macOS only with device management, and the browser keeps the setting in Secure Preferences, signed for the machine,
# so that a value written into the profile is reset. cdp.py calls the settings page's own setPref through the DevTools
# protocol, for which only this start of the browser opens a port. The session with the settings page is removed
# afterwards.
choose_restore() {
  local data=$1 page
  page=$([ "$APP" = chrome ] && echo chrome://settings/onStartup || echo edge://settings/startHomeNTP)
  open -a "$NAME" --args --remote-debugging-port=9333 '--remote-allow-origins=*'
  wait_for_app_window || log "$NAME opened no window"
  sleep 5
  python3 "$HERE/cdp.py" 9333 "$page" session.restore_on_startup 1 2>&1 | tee -a "$OUT/log.txt"
  sleep 2
  screencapture -x "$OUT/restore-setting.png"
  quit_app
  if grep -q '"restore_on_startup":1' "$data/Default/Secure Preferences" 2>/dev/null; then
    log "$NAME continues where it left off"
  else
    log "$NAME did not keep the setting to continue where it left off"
  fi
  rm -rf "$data/Default/Sessions"
}

setup_firefox() {
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
}

# Four Spaces, each with a window of another application.
setup_spaces() {
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

# Opens the application's three windows on Spaces 1 to 3, each with its page or document: a browser's first window from
# the Dock and its others with Command+N, Firefox's with its command line, and TextEdit's by opening the documents.
open_windows() {
  local n name
  for n in 1 2 3; do
    space_to $n
    name=$(echo page-one page-two page-three | cut -d' ' -f$n)
    if [ "$APP" = textedit ]; then
      open -a TextEdit "/tmp/pages/$name.txt"
    elif [ $n = 1 ]; then
      dock_click "$NAME"
      wait_for_app_window || log "$NAME opened no window"
      sleep 4
      load_page "$name"
    elif [ "$APP" = firefox ]; then
      /Applications/Firefox.app/Contents/MacOS/firefox -new-window "http://localhost:$PORT/$name.html" > /dev/null 2>&1 &
    else
      activate_app
      sleep 2
      keystroke n "command down"
      sleep 3
      load_page "$name"
    fi
    wait_for_title "$name" || log "no window shows $name"
    sleep 2
  done
}

activate_app() {
  osascript -e "tell application \"System Events\" to set frontmost of process \"$PROC\" to true"
}

quit_app() {
  activate_app
  sleep 1
  if [ "$APP" = chrome ] || [ "$APP" = edge ]; then
    # Quit in the application's menu, as Command+Q may ask to be held.
    osascript -e "tell application \"System Events\" to tell process \"$PROC\" to click (first menu item of menu 1 of menu bar item 2 of menu bar 1 whose name starts with \"Quit\")"
  else
    keystroke q "command down"
  fi
  local i
  for i in $(seq 30); do
    pgrep -x "$PROC" > /dev/null || return 0
    sleep 1
  done
  log "$NAME did not quit"
}

# Turns off and on again macOS switching to a Space with windows of an application when it activates, which the setup
# turns off while it opens windows on Spaces 2 and 3, as Firefox activates for a window opened with its command line.
swoosh() {
  if [ "$1" = off ]; then
    defaults write com.apple.dock workspaces-auto-swoosh -bool NO
  else
    defaults delete com.apple.dock workspaces-auto-swoosh
  fi
  killall Dock
  sleep 4
}

main() {
  PYTHON=$(for p in /Library/Frameworks/Python.framework/Versions/3.1*/bin/python3 /usr/bin/python3 python3; do "$p" -c "import tkinter" 2>/dev/null && echo "$p" && break; done)
  log "python with tkinter: $PYTHON"
  setup
  log "seed"
  swoosh off
  open_windows
  swoosh on
  sleep 16
  case "$SCENARIO" in
    A|B1|B2) quit_app ;;
    E) sleep 15; pkill -9 -x "$PROC"; sleep 3 ;;
  esac
  if [ "$SCENARIO" = F ] && [ "$APP" != firefox ]; then
    space_to 1
    activate_app
    sleep 1
  elif [ "$SCENARIO" = F ]; then
    space_to 1
    activate_app
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
    # A window of an application started without input of the user opens in the background, so the user clicks it.
    cliclick "c:280,180"
    sleep 1
  fi
  snapshot > "$OUT/before.json"
  screencapture -x "$OUT/before.png"
  log "trigger"
  case "$SCENARIO" in
    A|C|E) dock_click "$NAME" ;;
    B1|B2|D1|D2) key_code 36 ;;
    F) [ "$APP" = firefox ] || load "$RESTART_URL" ;;
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
