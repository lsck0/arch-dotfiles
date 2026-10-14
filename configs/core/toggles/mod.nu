use module.nu *

# the bar and the menu have no terminal to ask in: polkit lets an admin at the machine run this one root helper and
# start/stop the toggled units unprompted; lowering the firewall, portmaster or tor-router still asks (49-toggles.rules)
export def system [cfg: record] {
    [
        (file-copy toggle-root.nu /usr/local/bin/toggle-root --mode 755)
        (file-copy 49-toggles.rules /etc/polkit-1/rules.d/49-toggles.rules)
    ]
}
