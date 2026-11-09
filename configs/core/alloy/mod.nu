use module.nu *
use ../../../platforms/homelab.nu [HOMELAB]

# Ships this desktop's node metrics and journal to the homelab (Grafana: Prometheus desktops, Loki desktops), only on
# a machine the lab lists as a desktop and with its push credential (secrets keys/alloy-<host>, `user:password`).
export const meta = {packages: {pacman: [grafana-alloy]}}

const UNIT = "grafana-alloy.service"
const CONFIG = "/etc/grafana-alloy/config.alloy"
# root-only; systemd hands it to the service as a credential, so the alloy user never reads a file of its own
const PASSWORD = "/etc/grafana-alloy/push-password"
const DROPIN = "/etc/systemd/system/grafana-alloy.service.d/10-dotfiles.conf"

export def system [cfg: record] {
    let host = sys host | get hostname
    let credential = $env.DOTFILES_SECRETS? | default "/nonexistent" | path join $"alloy-($host)"
    if $host not-in $HOMELAB.push.desktops or not ($credential | path exists) { return [] }
    let password = open --raw $credential | str trim | split row ":" | skip 1 | str join ":"
    let restart = [systemctl try-restart $UNIT]
    [
        (file-text $PASSWORD $password --mode "600" --then $restart)
        (file-text $DROPIN $"[Service]\nLoadCredential=push:($PASSWORD)\n" --then [systemctl daemon-reload])
        (file-render config.alloy $CONFIG {HOST: $host, PROMETHEUS: $HOMELAB.push.prometheus, LOKI: $HOMELAB.push.loki}
            --then [systemctl reload-or-restart $UNIT])
        (unit-enable $UNIT --now)
    ]
}
