use module.nu *

export const meta = {packages: {native: [czmq-git ossec-hids-local]}}

const OSSEC_CONF = "/var/lib/ossec-hids/etc/ossec.conf"
const MARKER = "<!-- appended by the dotfiles (configs/base/ossec)"
const TMPFILES = "/etc/tmpfiles.d/ossec-alerts.conf"

export def system [cfg: record] {
    if not ("/var/lib/ossec-hids" | path exists) { return [] }
    [
        (group-admins ossec-alerts)
        (unit-file ossec-journal.service)
        (unit-enable ossec-server.target)
        (unit-enable ossec-journal.service)
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
    let ours = $lines | enumerate | where {|l| $l.item | str starts-with $MARKER } | get --optional 0.index
        | default ($lines | length)
    let shipped = $lines | first $ours | reduce --fold {out: [], skip: false} {|l, acc|
        if $l == "  <localfile>" { $acc | update skip true } else if $l == "  </localfile>" and $acc.skip {
            $acc | update skip false
        } else if $acc.skip { $acc } else { $acc | update out { append $l } }
    } | get out
    let want = $shipped | append (open --raw localfile.xml | lines) | str join "\n" | $"($in)\n"
    if $want != (open --raw $OSSEC_CONF) {
        $want | save --force $OSSEC_CONF
        ^systemctl try-restart ossec-logcollector.service
    }
}
