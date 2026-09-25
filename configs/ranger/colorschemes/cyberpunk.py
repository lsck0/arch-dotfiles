# This file is part of the arch-dotfiles ranger config.
# License: GNU GPL version 3, matching ranger's own colorscheme license.
#
# "cyberpunk": an accent-forward, dark, neon-terminal colorscheme.
# It only ever names the 8 ANSI color slots (black..white) plus the
# terminal "default" and the BRIGHT modifier. Those slots are painted
# by pywal (via colors-kitty.conf), so this scheme tracks the wallpaper
# palette for free: no fixed 256-cube hex values are used anywhere.
# Accent = ANSI cyan/magenta (pywal slots 6/5), matrix-green executables.

from __future__ import (absolute_import, division, print_function)

from ranger.gui.colorscheme import ColorScheme
from ranger.gui.color import (
    black, blue, cyan, green, magenta, red, white, yellow, default,
    normal, bold, reverse, dim, BRIGHT,
    default_colors,
)


class Cyberpunk(ColorScheme):
    # Loading bar rides the magenta accent slot.
    progress_bar_color = magenta

    def use(self, context):  # pylint: disable=too-many-branches,too-many-statements
        fg, bg, attr = default_colors

        if context.reset:
            return default_colors

        elif context.in_browser:
            if context.selected:
                # Selected row: neon accent bar via reverse video.
                attr = reverse | bold
            else:
                attr = normal
            if context.empty or context.error:
                bg = red
            if context.border:
                # Subtle borders: plain terminal default fg.
                fg = default
            if context.media:
                if context.image:
                    fg = yellow
                else:
                    fg = magenta
            if context.container:
                fg = red
            if context.directory:
                # Directories: bright neon cyan, bold.
                attr |= bold
                fg = cyan
                fg += BRIGHT
            elif context.executable and not \
                    any((context.media, context.container,
                         context.fifo, context.socket)):
                # Executables: matrix bright green.
                attr |= bold
                fg = green
                fg += BRIGHT
            if context.socket:
                attr |= bold
                fg = magenta
                fg += BRIGHT
            if context.fifo or context.device:
                fg = yellow
                if context.device:
                    attr |= bold
                    fg += BRIGHT
            if context.link:
                fg = cyan if context.good else magenta
            if context.tag_marker and not context.selected:
                attr |= bold
                if fg in (red, magenta):
                    fg = white
                else:
                    fg = magenta
                fg += BRIGHT
            if not context.selected and (context.cut or context.copied):
                # Cut/copied: dimmed so pending files recede.
                attr |= dim
                fg = white
            if context.main_column:
                if context.selected:
                    attr |= bold
                if context.marked:
                    # Marked files: bold magenta accent.
                    attr |= bold
                    fg = magenta
                    fg += BRIGHT
            if context.badinfo:
                if attr & reverse:
                    bg = magenta
                else:
                    fg = magenta

            if context.inactive_pane:
                fg = cyan

        elif context.in_titlebar:
            # Titlebar: bold accent, hostname/path in neon cyan.
            attr |= bold
            if context.hostname:
                fg = red if context.bad else cyan
            elif context.directory:
                fg = cyan
                fg += BRIGHT
            elif context.tab:
                if context.good:
                    bg = magenta
                    fg = black
            elif context.link:
                fg = cyan

        elif context.in_statusbar:
            if context.permissions:
                if context.good:
                    fg = cyan
                elif context.bad:
                    fg = magenta
            if context.marked:
                attr |= bold | reverse
                fg = magenta
                fg += BRIGHT
            if context.frozen:
                attr |= bold | reverse
                fg = cyan
                fg += BRIGHT
            if context.message:
                if context.bad:
                    attr |= bold
                    fg = red
                    fg += BRIGHT
            if context.loaded:
                bg = self.progress_bar_color
            if context.vcsinfo:
                fg = cyan
                attr &= ~bold
            if context.vcscommit:
                fg = yellow
                attr &= ~bold
            if context.vcsdate:
                fg = magenta
                attr &= ~bold

        if context.text:
            if context.highlight:
                attr |= reverse

        if context.in_taskview:
            if context.title:
                fg = cyan
            if context.selected:
                attr |= reverse
            if context.loaded:
                if context.selected:
                    fg = self.progress_bar_color
                else:
                    bg = self.progress_bar_color

        if context.vcsfile and not context.selected:
            attr &= ~bold
            if context.vcsconflict:
                fg = magenta
            elif context.vcsuntracked:
                fg = cyan
            elif context.vcschanged:
                fg = red
            elif context.vcsunknown:
                fg = red
            elif context.vcsstaged:
                fg = green
            elif context.vcssync:
                fg = green
            elif context.vcsignored:
                fg = default

        elif context.vcsremote and not context.selected:
            attr &= ~bold
            if context.vcssync or context.vcsnone:
                fg = green
            elif context.vcsbehind:
                fg = red
            elif context.vcsahead:
                fg = blue
            elif context.vcsdiverged:
                fg = magenta
            elif context.vcsunknown:
                fg = red

        return fg, bg, attr
