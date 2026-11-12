use module.nu *

export const meta = {packages: {native: [czmq-git ossec-hids-local]}}

const OSSEC_CONF = "/var/lib/ossec-hids/etc/ossec.conf"
const TMPFILES = "/etc/tmpfiles.d/ossec-alerts.conf"

export def system [cfg: record] {
    if not ("/var/lib/ossec-hids" | path exists) { return [] }
    [
        (group-admins ossec-alerts)
        (unit-file ossec-journal.service --enable)
        (unit-enable ossec-server.target)
        (dropin ossec-syscheckd.service syscheckd-idle.conf --name idle.conf)
        (file-copy 99-ossec-ac.rules /etc/udev/rules.d/99-ossec-ac.rules --then [udevadm control --reload])
        (step localfiles)
        (file-copy alerts-acl.conf $TMPFILES --then [systemd-tmpfiles --create $TMPFILES])
    ]
}

# Drops the shipped localfiles: they name syslog files arch never writes, each a 'Could not open file' per start.
export def localfiles []: nothing -> nothing {
    if (^systemctl is-active -q ossec-server.target | complete).exit_code == 0 {
        ^systemctl start ossec-journal.service
    }
    let lines = open --raw $OSSEC_CONF | lines
    # localfile.xml opens with its marker comment: everything from there on is the last run's copy
    let ours = open --raw localfile.xml | lines
    let at = $lines | enumerate | where item == $ours.0 | get --optional 0.index | default ($lines | length)
    let shipped = $lines | first $at | reduce --fold {out: [], skip: false} {|l, acc|
        if $l == "  <localfile>" { $acc | update skip true } else if $l == "  </localfile>" and $acc.skip {
            $acc | update skip false
        } else if $acc.skip { $acc } else { $acc | update out { append $l } }
    } | get out
    let want = $shipped | append $ours | str join "\n" | $"($in)\n"
    if $want != (open --raw $OSSEC_CONF) {
        $want | save --force $OSSEC_CONF
        ^systemctl try-restart ossec-logcollector.service
    }
}
