# Firefox launch and session restore on macOS

Tests of how Firefox, Safari, Chrome, Edge and TextEdit restore their windows on macOS, when they are launched from the
Dock, open a URL from another application, or restart, with windows on several Spaces. They are the macOS part of a
map of launch and window states across desktops, for [Mozilla bug 2090730](https://bugzilla.mozilla.org/show_bug.cgi?id=2090730).

The tests run on GitHub's hosted macOS runners. `probe` checks what a runner allows: the macOS version, System Integrity
Protection, the screen, the browsers it has, the accessibility permissions of the shell, creating and switching
Spaces, clicking the Dock, and screenshots, which it uploads as artifacts.
