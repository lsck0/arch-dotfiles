use module.nu *
use ../../../platforms/homelab.nu [HOMELAB]

# Ships this desktop's node metrics and journal to the homelab (Grafana: Prometheus desktops, Loki desktops), only on
# a machine the lab lists as a desktop and with its push credential (secrets keys/alloy/<host>, `user:password`).
# grafana-alloy-bin, Grafana's own build: Arch's grafana-alloy is built without journal support, so its
# loki.source.journal stays off. Until the mirror carries the bin package, whichever of the two is installed runs.
export const meta = {packages: {pacman: [grafana-alloy-bin]}, secrets: ["alloy/{host}"]}

const AC_RULES = "/etc/udev/rules.d/99-alloy-ac.rules"
# both packages' units pass $CUSTOM_ARGS to `alloy run`; this file is read after the package's own, which sets it empty
const ARGS = "CUSTOM_ARGS=\"--disable-reporting\"\n"

# the two packages' layouts: the bin one is upstream's (alloy.service, /etc/alloy), Arch's is renamed
const BUILDS = [
    {unit: "alloy.service", dir: "/etc/alloy", probe: "/usr/lib/systemd/system/alloy.service"}
    {unit: "grafana-alloy.service", dir: "/etc/grafana-alloy", probe: "/usr/lib/systemd/system/grafana-alloy.service"}
]

export def system [cfg: record] {
    let host = sys host | get hostname
    let credential = system-secret alloy $host
    let build = $BUILDS | where { $in.probe | path exists } | get --optional 0
    if $build == null or $host not-in $HOMELAB.push.desktops or not ($credential | path exists) { return [] }
    let password = open --raw $credential | str trim | split row ":" | skip 1 | str join ":"
    # root-only; systemd hands it to the service as a credential, so the alloy user never reads a file of its own
    let secret = $build.dir | path join push-password
    let args = $build.dir | path join dotfiles.env
    let restart = unit-restart $build.unit --if-running
    let dropin = [
        "[Unit]\nConditionACPower=true\n"
        "[Service]"
        $"LoadCredential=push:($secret)"
        # the journal group: Arch's sysusers adds it, upstream's does not
        "SupplementaryGroups=systemd-journal"
        # no usage report to stats.grafana.org
        $"EnvironmentFile=($args)"
    ] | to text
    [
        (file-text $secret $password --mode "600" --then $restart)
        (file-text $args $ARGS --then $restart)
        (file-text $"/etc/systemd/system/($build.unit).d/10-dotfiles.conf" $dropin
            --then [sh -c $"systemctl daemon-reload && systemctl try-restart ($build.unit)"])
        (file-render 99-alloy-ac.rules $AC_RULES {UNIT: $build.unit} --then (udev-reload))
        (file-render config.alloy ($build.dir | path join config.alloy)
            {HOST: $host, PROMETHEUS: $HOMELAB.push.prometheus, LOKI: $HOMELAB.push.loki} --then (unit-restart $build.unit --reload))
        (unit-enable $build.unit --now)
    ]
}
