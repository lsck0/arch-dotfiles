use module.nu *
use ../../../platforms/homelab.nu [HOMELAB]

# Ships this desktop's node metrics, its health (desktop-metrics.nu) and journal to the homelab (Grafana: Prometheus
# desktops, Loki desktops), only on a machine the lab lists as a desktop and with its push credential (secrets
# keys/alloy/<host>, `user:password`) or the password a run with it wrote; anywhere else the module declares nothing.
# grafana-alloy-bin, Grafana's own build: Arch's grafana-alloy is built without journal support, so its
# loki.source.journal stays off.
export const meta = {secrets: ["alloy/{host}"]}

# only where an owner logs in: it pushes to the owner's lab alone
export def packages [cfg: record]: nothing -> record {
    {pacman: (if (profile-owner) { [grafana-alloy-bin] } else { [] })}
}

const AC_RULES = "/etc/udev/rules.d/99-alloy-ac.rules"
# desktop-metrics' textfile, made only where alloy pushes: the user half runs only when it exists
const TEXTFILE_DIR = "/var/lib/node-textfile"
const TMPFILES = "/etc/tmpfiles.d/node-textfile.conf"
# the unit passes $CUSTOM_ARGS to `alloy run`; this file is read after the package's own, which sets it empty
const ARGS = "CUSTOM_ARGS=\"--disable-reporting\"\n"

const UNIT = "alloy.service"
const UNIT_FILE = "/usr/lib/systemd/system/alloy.service"
const ETC = "/etc/alloy"

export def system [cfg: record] {
    let host = sys host | get hostname
    let credential = system-secret alloy $host
    if not ($UNIT_FILE | path exists) or $host not-in $HOMELAB.push.desktops { return [] }
    # root-only; systemd hands it to the service as a credential, so the alloy user never reads a file of its own
    let secret = $ETC | path join push-password
    # a run with locked secrets is handed no credential: the password the last run wrote stays, so the push is never
    # undone
    let password = if ($credential | path exists) {
        open --raw $credential | str trim | split row ":" | skip 1 | str join ":"
    } else {
        try { open --raw $secret } catch { null }
    }
    if $password == null { return [] }
    let args = $ETC | path join dotfiles.env
    let restart = unit-restart $UNIT --if-running
    let dropin = [
        "[Unit]\nConditionACPower=true\n"
        "[Service]"
        $"LoadCredential=push:($secret)"
        # the journal group, which the package's alloy user is not in
        "SupplementaryGroups=systemd-journal"
        # no usage report to stats.grafana.org
        $"EnvironmentFile=($args)"
    ] | to text
    [
        (file-text $secret $password --mode "600" --then $restart)
        (file-text $args $ARGS --then $restart)
        (file-text $"/etc/systemd/system/($UNIT).d/10-dotfiles.conf" $dropin
            --then [sh -c $"systemctl daemon-reload && systemctl try-restart ($UNIT)"])
        (file-render config/99-alloy-ac.rules $AC_RULES {UNIT: $UNIT} --then (udev-reload))
        (file-copy config/node-textfile.conf $TMPFILES --then [systemd-tmpfiles --create $TMPFILES])
        (file-copy scripts/desktop-metrics.nu /usr/local/bin/desktop-metrics --mode 755)
        (unit-file services/desktop-metrics.service)
        (unit-timer desktop-metrics.timer "Desktop health metrics every 5 minutes (system half)" --boot 2min
            --every 5min --enable --now)
        (file-render config/config.alloy ($ETC | path join config.alloy)
            {HOST: $host, PROMETHEUS: $HOMELAB.push.prometheus, LOKI: $HOMELAB.push.loki, TEXTFILE: $TEXTFILE_DIR}
            --then (unit-restart $UNIT --reload))
        (unit-enable $UNIT --now)
    ]
}

# The login's half of desktop-metrics, only once the system half made its directory (a lab-listed desktop with its
# credential).
export def link [cfg: record] {
    if not ($TEXTFILE_DIR | path exists) or not ("/usr/local/bin/desktop-metrics" | path exists) { return [] }
    [
        (unit-file services/desktop-metrics-user.service)
        (unit-timer desktop-metrics-user.timer "Desktop health metrics every 5 minutes (user half)" --startup 2min
            --every 5min --enable --now)
    ]
}
