import os

config.load_autoconfig()

# ---------------------------------------------------------------------------
# ayu
# ---------------------------------------------------------------------------
bg = "#1f2430"
bg_alt = "#232834"
fg = "#cbccc6"
accent = "#ffcc66"  # ayu orange/yellow
blue = "#73d0ff"
green = "#bae67e"
red = "#ff3333"
comment = "#5c6773"
sel = "#34455a"

# completion popup
c.colors.completion.fg = fg
c.colors.completion.odd.bg = bg
c.colors.completion.even.bg = bg_alt
c.colors.completion.category.bg = bg
c.colors.completion.category.fg = accent
c.colors.completion.category.border.top = bg
c.colors.completion.category.border.bottom = bg
c.colors.completion.item.selected.bg = sel
c.colors.completion.item.selected.fg = fg
c.colors.completion.item.selected.border.top = sel
c.colors.completion.item.selected.border.bottom = sel
c.colors.completion.item.selected.match.fg = accent
c.colors.completion.match.fg = accent
c.colors.completion.scrollbar.fg = fg
c.colors.completion.scrollbar.bg = bg

# statusbar
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

# tabs
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

# hints (f-mode link labels)
c.colors.hints.bg = accent
c.colors.hints.fg = bg
c.colors.hints.match.fg = red
c.hints.border = "0px"

# messages
c.colors.messages.error.bg = red
c.colors.messages.warning.bg = accent
c.colors.messages.info.bg = bg

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
c.tabs.position = "top"
c.tabs.show = "multiple"  # hide tabbar when only 1 tab
c.tabs.indicator.width = 2
c.statusbar.show = "in-mode"  # hide statusbar except command/insert modes
c.scrolling.smooth = True
c.fonts.default_family = "JetBrainsMono Nerd Font"
c.fonts.default_size = "11pt"
c.fonts.hints = "bold 11pt default_family"

# web content dark preference (let sites use their own dark mode)
c.colors.webpage.preferred_color_scheme = "dark"
c.colors.webpage.bg = bg

# ---------------------------------------------------------------------------
# homepage / new tab
# ---------------------------------------------------------------------------
_startpage = "file://" + os.path.expanduser("~/.config/qutebrowser/startpage.html")
c.url.start_pages = [_startpage]
c.url.default_page = _startpage

# ---------------------------------------------------------------------------
# search engines
# ---------------------------------------------------------------------------
c.url.searchengines = {
    "DEFAULT": "https://www.google.com/search?q={}",
    "ap": "https://archlinux.org/packages/?q={}",
    "aur": "https://aur.archlinux.org/packages?K={}",
    "aw": "https://wiki.archlinux.org/?search={}",
    "gh": "https://github.com/search?q={}",
    "nlab": "https://ncatlab.org/nlab/search?query={}",
    "tw": "https://www.twitch.tv/search?term={}",
    "w": "https://en.wikipedia.org/w/index.php?search={}",
    "yt": "https://youtube.com/results?search_query={}",
}

# ---------------------------------------------------------------------------
# keybindings
# ---------------------------------------------------------------------------
config.bind("J", "tab-prev")
config.bind("K", "tab-next")

config.bind("<Alt+x>", "tab-close")
config.bind("<Alt+c>", "open -t")  # new tab
for i in range(1, 10):
    config.bind("<Alt+{}>".format(i), "tab-focus {}".format(i))

config.bind(",v", "mode-enter passthrough")

config.bind("y", "yank selection", mode="caret")
config.bind("Y", "yank selection", mode="caret")
