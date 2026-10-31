use module.nu *

export const meta = {packages: {native: [polkit tor]}, inputs: [/usr/bin/tor]}

const ROUTER = "/usr/local/bin/tor-router"
const PERSONA = "/etc/NetworkManager/dispatcher.d/90-anonymous-persona"

# toron and toroff switch the route tor-router sets up, so they come with tor as the router does
export def link [cfg: record] {
    if (which tor | is-empty) { [] } else { shell-aliases tor }
}

export def system [cfg: record] {
    # no tor-router without the tor it routes into
    if $env.FORM_FACTOR? == "wsl" or (which tor | is-empty) { return [] }
    [
        (file-copy torrc /etc/tor/torrc)
        # vendored from edu4rdshl/tor-router: no package upgrade can restore its fail-open unit
        (file-copy tor-router.nu $ROUTER --mode 755
            --then [sh -c $"! systemctl is-active -q tor-router.service || ($ROUTER) start"])
        # no Requires=tor.service, so a tor restart cannot tear the table down; once in place the persona dispatcher
        # switches a foreign link to tor, so a fresh install off home goes onto tor without waiting for a link event
        (unit-file tor-router.service --then [sh -c $"[ ! -x ($PERSONA) ] || exec ($PERSONA) '' tor-arrived"])
    ]
}
