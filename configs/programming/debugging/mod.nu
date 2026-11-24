use module.nu *

export const meta = {
    reads: [desktop/hyprland]
    packages: {
        pacman: [
            bloaty bpftrace codelldb-bin delve drgn flamegraph flamelens heaptrack hotspot kcachegrind lcov lldb ltrace
            py-spy raddebugger reptyr rr samply speedscope strace strace-tui tracy valgrind
        ]
    }
}

# raddbg is an X11 app that knows no display scale: its windows get the font size times the X11 scale (21 at 2)
export const options = {
    raddbg_font_px: {
        type: float
        default: 10.5
        doc: "raddbg's font size before the X11 scale; set once per value, a size picked in the app stays"
        label: "raddbg font size"
        min: 6
        max: 32
        step: 0.5
    }
}

export def link [cfg: record] {
    let user = xdg config raddbg default.raddbg_user
    let font = $cfg.raddbg_font_px * (xwayland-scale-for $cfg) | math round | into string
    [
        # once per scale, so a size picked in the app afterwards stays; pending until raddbg writes the file on its
        # first start, so the key is recorded only once a size got in
        (if (which raddbg | is-not-empty) { step raddbg-font $font --creates $user --requires $user --key $font })
        (if (which tracy-profiler | is-not-empty) {
            ini-merge (xdg config tracy tracy.ini) {achievements: {enabled: 0, asked: 1}} --missing-only
        })
    ] | compact
}

# Sets every window's font size in the user file raddbg keeps.
export def raddbg-font [size: string]: nothing -> nothing {
    let user = xdg config raddbg default.raddbg_user
    if not ($user | path exists) {
        print "raddbg has not written its user file yet"
        exit $EXIT_PENDING
    }
    open --raw $user | str replace --all --regex '(?m)^(\s*font_size:)\s*\d+' $"${1} ($size)" | save --force $user
}
