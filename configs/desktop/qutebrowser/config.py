# ruff: noqa: F821  # qutebrowser injects `config` and `c` into this file's namespace at load time
import json
import os

config.load_autoconfig()

_wal_dir = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "wal")

_fb = {
    "special": {"background": "#1f2430", "foreground": "#cbccc6"},
    "colors": {"color0": "#232834", "color1": "#ff3333", "color2": "#bae67e", "color4": "#73d0ff", "color8": "#5c6773"},
}
_wal = _fb
try:
    with open(os.path.join(_wal_dir, "colors.json")) as _f:
        _wal = json.load(_f)
except OSError, ValueError:
    pass

# the metrics a theme set (configs/core/wallust), its defaults when the file is missing or invalid
_style = {"light_luminance": 0.4, "radius_px": 2}
try:
    with open(os.path.expanduser("~/.config/dotfiles/style.json")) as _f:
        _style.update(json.load(_f))
except OSError, ValueError:
    pass

# the font a theme or toggle-font set (configs/core/wallust/font.nu), its defaults when unset
_font = {"family": "Kode Mono", "ui_size": 11}
try:
    with open(os.path.join(_wal_dir, "font.json")) as _f:
        _font.update(json.load(_f))
except OSError, ValueError:
    pass


# the chrome roles the theme verb conditioned from the palette (mod.nu chrome-colors), the raw slots without it
_chrome = {}
try:
    with open(os.path.join(_wal_dir, "qutebrowser-colors.json")) as _f:
        _chrome = json.load(_f)
except OSError, ValueError:
    pass


def _c(section, key):
    return _wal.get(section, {}).get(key) or _fb[section][key]


def _role(name, section, key):
    return _chrome.get(name) or _c(section, key)


bg = _role("bg", "special", "background")
bg_alt = _role("bg_alt", "colors", "color0")
fg = _role("fg", "special", "foreground")


def _luminance(hex_color):
    h = hex_color.lstrip("#")
    try:
        channels = [int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    except ValueError, IndexError:
        return 0.0
    r, g, b = (x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in channels)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def _is_light(hex_color):
    return _luminance(hex_color) >= _style["light_luminance"]


accent = _role("accent", "colors", "color4")
blue = _c("colors", "color4")
green = _c("colors", "color2")
red = _c("colors", "color1")
comment = _role("muted", "colors", "color8")
sel = _role("selection_bg", "colors", "color8")
sel_fg = _role("selection_fg", "special", "foreground")
sel_match = _role("selection_match", "colors", "color4")
hint_bg = _role("hint_bg", "colors", "color4")
hint_fg = _role("hint_fg", "special", "background")
hint_match = _role("hint_match", "colors", "color1")

c.colors.completion.fg = fg
c.colors.completion.odd.bg = bg
c.colors.completion.even.bg = bg_alt
c.colors.completion.category.bg = bg
c.colors.completion.category.fg = accent
c.colors.completion.category.border.top = bg
c.colors.completion.category.border.bottom = bg
c.colors.completion.item.selected.bg = sel
c.colors.completion.item.selected.fg = sel_fg
c.colors.completion.item.selected.border.top = sel
c.colors.completion.item.selected.border.bottom = sel
c.colors.completion.item.selected.match.fg = sel_match
c.colors.completion.match.fg = accent
c.colors.completion.scrollbar.fg = fg
c.colors.completion.scrollbar.bg = bg

c.colors.statusbar.normal.bg = bg
c.colors.statusbar.normal.fg = fg
c.colors.statusbar.insert.bg = green
c.colors.statusbar.insert.fg = bg
c.colors.statusbar.command.bg = bg
c.colors.statusbar.command.fg = fg
c.colors.statusbar.url.fg = fg
c.colors.statusbar.url.success.https.fg = green
c.colors.statusbar.url.hover.fg = blue
c.colors.statusbar.progress.bg = accent

c.colors.tabs.bar.bg = bg
c.colors.tabs.odd.bg = bg_alt
c.colors.tabs.even.bg = bg_alt
c.colors.tabs.odd.fg = comment
c.colors.tabs.even.fg = comment
c.colors.tabs.selected.odd.bg = bg
c.colors.tabs.selected.even.bg = bg
c.colors.tabs.selected.odd.fg = accent
c.colors.tabs.selected.even.fg = accent
c.colors.tabs.indicator.start = blue
c.colors.tabs.indicator.stop = green

c.colors.hints.bg = hint_bg
c.colors.hints.fg = hint_fg
c.colors.hints.match.fg = hint_match
c.hints.border = "0px"
c.hints.radius = _style["radius_px"]

c.colors.messages.error.bg = red
c.colors.messages.warning.bg = accent
c.colors.messages.info.bg = bg

c.tabs.position = "top"
c.tabs.show = "multiple"
c.tabs.indicator.width = 2
c.statusbar.show = "in-mode"
c.scrolling.smooth = True
c.fonts.default_family = _font["family"]
c.fonts.default_size = f"{_font['ui_size']}pt"
c.fonts.hints = f"bold {_font['ui_size']}pt default_family"

c.colors.webpage.preferred_color_scheme = "light" if _is_light(bg) else "dark"
c.colors.webpage.bg = bg

_startpage = "file://" + os.path.expanduser("~/.config/qutebrowser/startpage.html")
c.url.start_pages = [_startpage]
c.url.default_page = _startpage
config.set("content.local_content_can_access_remote_urls", True, _startpage)

_search = "https://duckduckgo.com/?q={}"
try:
    with open(os.path.expanduser("~/.config/qutebrowser/search-url")) as _f:
        _search = _f.read().strip()
except OSError:
    pass
c.url.searchengines = {
    "DEFAULT": _search,
    "ddg": "https://duckduckgo.com/?q={}",
    "g": "https://www.google.com/search?q={}",
    "ap": "https://archlinux.org/packages/?q={}",
    "aur": "https://aur.archlinux.org/packages?K={}",
    "aw": "https://wiki.archlinux.org/?search={}",
    "gh": "https://github.com/search?q={}",
    "nlab": "https://ncatlab.org/nlab/search?query={}",
    "tw": "https://www.twitch.tv/search?term={}",
    "w": "https://en.wikipedia.org/w/index.php?search={}",
    "yt": "https://youtube.com/results?search_query={}",
}

c.content.webrtc_ip_handling_policy = "default-public-interface-only"
c.content.cookies.accept = "no-3rdparty"
c.content.blocking.method = "both"

config.bind("J", "tab-prev")
config.bind("K", "tab-next")

config.bind("<Alt+x>", "tab-close")
config.bind("<Alt+c>", "open -t")
for i in range(1, 10):
    config.bind(f"<Alt+{i}>", f"tab-focus {i}")

config.bind(",v", "mode-enter passthrough")

config.bind("y", "yank selection", mode="caret")
config.bind("Y", "yank selection", mode="caret")
