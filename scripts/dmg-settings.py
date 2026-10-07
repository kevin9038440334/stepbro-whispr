# Ajustes de dmgbuild para el instalador. Los usa scripts/make-dmg.sh.
# Las posiciones son el centro de cada icono, medidas desde arriba a la izquierda de la ventana;
# coinciden con las del fondo (scripts/make-dmg-background.swift).
import os.path

app = defines["app"]
app_name = os.path.basename(app)

format = "ULFO"  # LZFSE: comprime bien y se abre rápido (macOS 10.11 o posterior)
filesystem = "APFS"
files = [app]
symlinks = {"Aplicaciones": "/Applications"}
icon = defines["icon"]

background = defines["background"]
window_rect = ((200, 140), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
icon_size = 112
text_size = 13
icon_locations = {
    app_name: (170, 196),
    "Aplicaciones": (470, 196),
}
