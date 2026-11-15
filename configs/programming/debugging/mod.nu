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

# raddbg is an X11 app that knows no display scale: its windows get this size times the X11 scale (21 at 2)
const RADDBG_FONT_PX = 10.5

export def link [cfg: record] {
    let user = xdg config raddbg default.raddbg_user
    let font = $RADDBG_FONT_PX * (xwayland-scale-for $cfg) | math round | into string
    [
        # once per scale, so a size picked in the app afterwards stays; raddbg writes the file on its first start
        (if (which raddbg | is-not-empty) { step raddbg-font $font --creates $user --key $font })
        (if (which tracy-profiler | is-not-empty) {
            ini-merge (xdg config tracy tracy.ini) {achievements: {enabled: 0, asked: 1}} --missing-only
        })
    ] | compact
}

# Sets every window's font size in the user file raddbg keeps.
export def raddbg-font [size: string]: nothing -> nothing {
    let user = xdg config raddbg default.raddbg_user
    if not ($user | path exists) { return }
    open --raw $user | str replace --all --regex '(?m)^(\s*font_size:)\s*\d+' $"${1} ($size)" | save --force $user
}
