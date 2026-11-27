# Firefox launch and session restore on macOS

Tests of how Firefox, Safari, Chrome, Edge and TextEdit restore their windows on macOS, when they are launched from the
Dock, open a URL from another application, or restart, with windows on several Spaces. They are the macOS part of a
map of launch and window states across desktops, for [Mozilla bug 2090730](https://bugzilla.mozilla.org/show_bug.cgi?id=2090730).

The tests run on GitHub's hosted macOS runners. `probe` checks what a runner allows: the macOS version, System Integrity
Protection, the screen, the browsers it has, the accessibility permissions of the shell, creating and switching
Spaces, clicking the Dock, and screenshots, which it uploads as artifacts.

`matrix` runs the scenarios of the map with Firefox, one job each: `matrix/matrix.sh` installs the Firefox build from
archive.mozilla.org, makes it the default browser, creates four Spaces with a window of another application on each
(`matrix/other-app.py`), opens Firefox's three windows on Spaces 1 to 3, and launches, links, crashes or restarts it as
the scenario says, with real clicks on the Dock and key presses. Each job uploads `result.json` with the windows on
screen and the frontmost window before and after, the windows of each Space at the end, and screenshots.

`others` runs the same scenarios with Chrome, Edge, Safari and TextEdit. Chrome and Edge continue where they left off as
a user chooses it, as their policy for it applies on macOS only with device management: `matrix.sh` clicks the option
on their startup settings page, and Edge's questions at its first start, finding them on the screen with macOS's text
recognition (`matrix/find-text.swift`). macOS rearranges Spaces by their most recent use, so `matrix.sh` tells a Space by
the window of the other application on it.

`gtk` checks what GTK's macOS backend shows in the macOS menu bar, for comparison with global menus on Linux:
`gtk/app.py` is a GTK 4 application with a menu bar set with `gtk_application_set_menubar()`, or with only a header bar
and its primary menu, as GNOME applications have, with GTK alone or with libadwaita. `gtk/run.sh` installs GTK from
Homebrew, runs one of them, activates it with a click on its window, and records the menus and items System Events
reports for its menu bar, with screenshots.
