use module.nu *
use ../../../platforms/homelab.nu [HOMELAB]

# The Wazuh agent on a machine the lab lists as a desktop, while the lab runs a manager: journal, file integrity on
# /etc and /boot, rootcheck, the CIS Arch policy and the inventory go to the manager, which alerts. Enrolls by the
# lab's password (secrets keys/<HOMELAB.wazuh.secret>) under the hostname; anywhere else the module declares nothing.
# wazuh-agent is the own pkgbuild at the manager's version: an agent never runs newer than its manager
export const meta = {packages: {native: [wazuh-agent]}, secrets: [wazuh-enrollment-password]}

const OSSEC = "/var/ossec"
const UNIT = "wazuh-agent.service"

def wanted []: nothing -> bool {
    $HOMELAB.wazuh != null and (sys host | get hostname) in $HOMELAB.push.desktops
}

export def system [cfg: record] {
    if not (wanted) or not ($OSSEC | path join bin wazuh-agentd | path exists) { return [] }
    let password = system-secret $HOMELAB.wazuh.secret
    if not ($password | path exists) { return [] }
    let host = sys host | get hostname
    # the daemons run as the wazuh group and read both; the password only for an enrollment
    let own = {|file| [sh -c $"chown root:wazuh ($file) && systemctl try-restart ($UNIT)"] }
    let conf = $OSSEC | path join etc ossec.conf
    let pass = $OSSEC | path join etc authd.pass
    [
        (file-text $pass (open --raw $password | str trim) --mode "640" --then (do $own $pass))
        (file-render ossec.conf $conf {
            MANAGER: $HOMELAB.wazuh.manager, EVENTS: $HOMELAB.wazuh.events, ENROLLMENT: $HOMELAB.wazuh.enrollment, HOST: $host
        } --mode "640" --then (do $own $conf))
        (unit-enable $UNIT --now)
    ]
}
