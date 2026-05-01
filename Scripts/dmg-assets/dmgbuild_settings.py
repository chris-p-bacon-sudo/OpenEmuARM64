# dmgbuild_settings.py
#
# Read by `dmgbuild -s dmgbuild_settings.py "OpenEmu-Silicon" output.dmg`.
# dmgbuild writes the .DS_Store binary blob directly via the mac_alias
# Python library — it does NOT call AppleScript or Finder. This sidesteps
# every macOS 26 (Tahoe) Finder/alias-bookmark regression we hit with
# the previous AppleScript-based pipeline.
#
# The app path is passed via the APP_PATH environment variable so the
# settings file works for both the local Debug build and the CI archive.

import os

# ── Volume + format ──────────────────────────────────────────────────────────
volume_name = "OpenEmu-Silicon"
format      = "UDZO"
filesystem  = "HFS+"

# ── Window geometry ──────────────────────────────────────────────────────────
# Window position (x, y) is the top-left on the user's screen at first open;
# size is logical points (full window including title-bar chrome).
# Total height = 680 (background) + 28 (title bar) + 12 (slack for status row
# Finder shows on macOS 26 even with show_status_bar=False) = 720.
window_rect    = ((240, 50), (960, 720))
default_view   = "icon-view"
show_status_bar = False
show_toolbar    = False
show_pathbar    = False
show_sidebar    = False
sidebar_width   = 0

# ── Background ───────────────────────────────────────────────────────────────
# 1920 × 1360 PNG tagged 144 DPI — Finder displays as 960 × 680 logical @2×.
# Path passed via BG_PATH env var by make-dmg.sh because dmgbuild exec()'s this
# file and __file__ isn't defined in that context.
background = os.environ["BG_PATH"]

# ── Icon view options ────────────────────────────────────────────────────────
icon_size       = 128
text_size       = 12
include_icon_view_settings = "auto"
include_list_view_settings = "auto"

# ── Contents ─────────────────────────────────────────────────────────────────
# files: real items copied into the DMG. APP_PATH is set by make-dmg.sh.
# symlinks: handled separately so we get a real Finder alias to /Applications.
files = [os.environ["APP_PATH"]]
symlinks = {"Applications": "/Applications"}

# Icon centre coordinates in logical points.
# Must match the arrow endpoints in background.html:
#   left  pedestal centre  (240, 340)
#   right cartridge centre (720, 340)
icon_locations = {
    "OpenEmu.app":  (240, 340),
    "Applications": (720, 340),
}
