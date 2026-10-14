use module.nu *

# the bar has no terminal to ask in: polkit runs this root helper unprompted for an admin (49-toggles.rules)
export def system [cfg: record] {
    [
        (file-copy toggle-root.nu /usr/local/bin/toggle-root --mode 755)
        (file-copy 49-toggles.rules /etc/polkit-1/rules.d/49-toggles.rules)
    ]
}
