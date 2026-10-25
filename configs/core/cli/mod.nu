use module.nu *

# arch-wiki-lite (wiki-search) and tealdeer keep the arch wiki and the tldr pages offline, beside man-db
export const meta = {
    packages: {pacman: [
        arch-wiki-lite bind bpftop caligula chafa clonezilla cmatrix croc direnv diskwatch dua-cli dwarfs dysk eza fd
        ffmpeg fzf gping gum ipython just kmon lazyjournal lolcat lshw mtools netkit-bsd-finger ntfs-3g openbsd-netcat
        ouch pandoc-cli parallel pdftk procs rar rsync rustnet s-tui sd socat sshfs sshpass superseedr tailspin
        tar-scripts tealdeer tparted-bin trippy usbtree ventoy-bin whois wiki-tui xdg-ninja xdg-user-dirs xdg-utils
        zoxide
    ]}
}

def tldr-pages []: nothing -> path {
    $env.TEALDEER_CACHE_DIR? | default ($nu.home-dir | path join .local share tealdeer) | path join tldr-pages
}

export def link [cfg: record] {
    [
        (file-copy tealdeer.toml ($nu.home-dir | path join .config tealdeer config.toml))
        (unit-file tldr-update.service)
        (unit-file tldr-update.timer --enable --now)
        # the first fetch here, so the pages are there before the timer's first run
        (if (^pacman -Q tealdeer | complete).exit_code != 0 { [] } else {
            exec tldr-pages [env $"TEALDEER_CACHE_DIR=(tldr-pages | path dirname)" tldr --update] --creates (tldr-pages)
        })
    ]
}
