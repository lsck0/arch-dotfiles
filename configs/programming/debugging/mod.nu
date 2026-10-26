use module.nu *

export const meta = {
    packages: {
        pacman: [
            bloaty bpftrace codelldb-bin delve drgn flamegraph flamelens heaptrack hotspot kcachegrind lcov lldb ltrace
            py-spy raddebugger reptyr rr samply speedscope strace strace-tui tracy valgrind
        ]
    }
}

export def link [cfg: record] {
    if (which tracy-profiler | is-empty) { return [] }
    ini-merge (xdg config tracy tracy.ini) {achievements: {enabled: 0, asked: 1}} --missing-only
}
