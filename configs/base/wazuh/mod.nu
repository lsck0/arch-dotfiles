use module.nu *
use ../../../platforms/homelab.nu [HOMELAB]

# The Wazuh agent on a machine the lab lists as a desktop, while the lab runs a manager: journal, file integrity on
# /etc and /boot, rootcheck, the CIS Arch policy and the inventory go to the manager, which alerts. Enrolls by the
# lab's password (secrets keys/<HOMELAB.wazuh.secret>) under the hostname; anywhere else the module declares nothing.
# wazuh-agent is the own pkgbuild at the manager's version: an agent never runs newer than its manager
export const meta = {secrets: [wazuh-enrollment-password]}

# only where an owner logs in: the lab enrolls its owner's desktops alone, and the package comes from [lsck0] only,
# which a machine off the lab leaves out while it does not answer
export def packages [cfg: record]: nothing -> record {
    {native: (if (profile-owner) { [wazuh-agent] } else { [] })}
}

const OSSEC = "/var/ossec"
const UNIT = "wazuh-agent.service"

def wanted []: nothing -> bool {
    $HOMELAB.wazuh != null and (sys host | get hostname) in $HOMELAB.push.desktops
}

export def system [cfg: record] {
    if not (wanted) or not ($OSSEC | path join bin wazuh-agentd | path exists) { return [] }
    let conf = $OSSEC | path join etc ossec.conf
    let pass = $OSSEC | path join etc authd.pass
    # a run with locked secrets is handed none: the password the last run wrote stays, so the agent is never undone
    let password = [(system-secret $HOMELAB.wazuh.secret) $pass] | where { path exists } | get --optional 0
    if $password == null { return [] }
    let host = sys host | get hostname
    # the daemons run as the wazuh group and read both; the password only for an enrollment
    let own = {|file| [sh -c $"chown root:wazuh ($file) && systemctl try-restart ($UNIT)"] }
    [
        (file-text $pass (open --raw $password | str trim) --mode "640" --then (do $own $pass))
        (file-render config/ossec.conf $conf {
            MANAGER: $HOMELAB.wazuh.manager, EVENTS: $HOMELAB.wazuh.events, ENROLLMENT: $HOMELAB.wazuh.enrollment, HOST: $host
        } --mode "640" --then (do $own $conf))
        (dropin $UNIT services/start-timeout.conf)
        (unit-enable $UNIT --now)
    ]
}
