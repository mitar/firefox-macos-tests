#!/usr/bin/env python3
"""A GTK 4 application for checking what GTK's macOS backend shows in the macOS menu bar.

Usage: app.py menubar|primary|adw

menubar  A GtkApplication with a menu bar set with gtk_application_set_menubar(), File and Edit, as older GNOME
         applications have.
primary  No menu bar, but a header bar with a primary menu, a GtkMenuButton with its primary property set, which F10
         opens, as GNOME applications have.
adw      The same with libadwaita, AdwApplication, AdwApplicationWindow and AdwHeaderBar, as current GNOME applications
         are built.

Each primary menu has Preferences, Keyboard Shortcuts and About, as GNOME applications have, and every application has
Quit with Cmd+Q. The application prints the name of each action it activates.
"""

import sys

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

variant = sys.argv[1]
if variant == "adw":
    gi.require_version("Adw", "1")
    from gi.repository import Adw  # noqa: E402


def add_actions(app):
    for name in ("new", "copy", "preferences", "shortcuts", "about", "quit"):
        action = Gio.SimpleAction.new(name, None)
        action.connect("activate", lambda _action, _parameter, name=name: print("activate", name, flush=True))
        app.add_action(action)
    app.set_accels_for_action("app.quit", ["<Primary>q"])


def primary_menu():
    menu = Gio.Menu()
    menu.append("_Preferences", "app.preferences")
    menu.append("_Keyboard Shortcuts", "app.shortcuts")
    menu.append("_About Test", "app.about")
    return menu


def on_activate(app):
    add_actions(app)
    if variant == "menubar":
        menubar = Gio.Menu()
        file_menu = Gio.Menu()
        file_menu.append("_New", "app.new")
        file_menu.append("_Quit", "app.quit")
        menubar.append_submenu("_File", file_menu)
        edit_menu = Gio.Menu()
        edit_menu.append("_Copy", "app.copy")
        menubar.append_submenu("_Edit", edit_menu)
        app.set_menubar(menubar)
        window = Gtk.ApplicationWindow(application=app, title="GTK menubar test")
        window.set_show_menubar(True)
        window.set_child(Gtk.Label(label="menubar"))
    else:
        button = Gtk.MenuButton(icon_name="open-menu-symbolic", menu_model=primary_menu(), primary=True)
        if variant == "adw":
            window = Adw.ApplicationWindow(application=app, title="GTK adw test")
            header = Adw.HeaderBar()
            header.pack_end(button)
            view = Adw.ToolbarView()
            view.add_top_bar(header)
            view.set_content(Gtk.Label(label="adw"))
            window.set_content(view)
        else:
            window = Gtk.ApplicationWindow(application=app, title="GTK primary test")
            header = Gtk.HeaderBar()
            header.pack_end(button)
            window.set_titlebar(header)
            window.set_child(Gtk.Label(label="primary"))
    window.set_default_size(600, 400)
    window.present()


GLib.set_application_name(f"GtkMenuTest {variant}")
application = (Adw.Application if variant == "adw" else Gtk.Application)(
    application_id=f"org.example.GtkMenuTest.{variant.capitalize()}")
application.connect("activate", on_activate)
application.run([])
