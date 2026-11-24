"""A window of another application for the launch matrix on macOS, with a focused button when given a URL, which
opens the URL in the default browser as clicking a link in an application does, once the user presses Return.

Usage: python3 other-app.py TITLE [URL]
"""

import sys
import tkinter
import webbrowser

root = tkinter.Tk()
root.title(sys.argv[1])
# The window with a link in the top left corner, so that it is not behind the others, which are in the middle.
root.geometry("400x200+80+80" if len(sys.argv) > 2 else "400x200+300+250")
if len(sys.argv) > 2:
    button = tkinter.Button(root, text="Open the link", command=lambda: webbrowser.open(sys.argv[2]))
    button.pack(padx=20, pady=20)
    root.bind("<Return>", lambda event: button.invoke())
    button.focus_set()
else:
    tkinter.Label(root, text=sys.argv[1]).pack(padx=20, pady=20)
root.lift()
root.mainloop()
