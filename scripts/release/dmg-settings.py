# dmgbuild settings for the Mumbli installer disk image.
#
# Deliberately has no background artwork: the layout alone (fixed window, icon
# view, large icons, app on the left and the Applications alias on the right)
# reads as intentional without inventing brand design.
#
# dmgbuild writes the .DS_Store directly via the ds_store library rather than
# driving Finder over AppleScript. That matters because this runs on a headless
# CI runner, where Finder automation is the classic source of intermittent
# release failures.
#
# usage: dmgbuild -s dmg-settings.py "<volume name>" <out.dmg>
#        DMG_APP_PATH must point at the signed .app to package.

import os

app_path = os.environ["DMG_APP_PATH"]
app_name = os.path.basename(app_path)

# Match the previous `hdiutil create -format UDZO` output so the published
# artifact stays a compressed read-only image.
format = "UDZO"
size = None  # let dmgbuild measure the contents

files = [app_path]
symlinks = {"Applications": "/Applications"}

# ((x, y), (width, height)) in screen coordinates.
window_rect = ((240, 240), (560, 380))
default_view = "icon-view"

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 13
label_pos = "bottom"

# Free placement, not a grid: the two icons are positioned explicitly below.
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)

# Coordinates are the icon centres within the window's content area. Kept
# symmetric about the horizontal centre (560 / 2 = 280) so the pair looks
# balanced, with room under each icon for its label.
icon_locations = {
    app_name: (150, 170),
    "Applications": (410, 170),
}

background = None
badge_icon = None
