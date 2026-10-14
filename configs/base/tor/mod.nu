use module.nu *

export const meta = {packages: {native: [tor]}}

const ROUTER = "/usr/local/bin/tor-router"

# real files in /etc, tor runs as its own user and must not depend on /home
export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    [
        (file-copy torrc /etc/tor/torrc)
        # vendored from edu4rdshl/tor-router: no package upgrade can restore its fail-open unit
        (file-copy tor-router.nu $ROUTER --mode 755
            --then [sh -c $"! systemctl is-active -q tor-router.service || ($ROUTER) start"])
        # no Requires=tor.service, so a tor restart cannot tear the table down
        (unit-file tor-router.service)
    ]
}
