# dmgbuild settings for Screen-Setter.dmg: the app on the left, Applications on the right.
# build.sh passes -D app=<path to Screen Setter.app> -D background=<path to dmg-background.tiff>.
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild injects `defines`)
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extension = [app_name]

background = defines["background"]  # noqa: F821
window_rect = ((200, 120), (600, 380))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
icon_locations = {
    app_name: (160, 180),
    "Applications": (440, 180),
}
