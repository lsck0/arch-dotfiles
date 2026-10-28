use module.nu *

export const meta = {
    packages: {
        pacman: [cups cups-pdf cups-pk-helper ipp-usb print-manager sane sane-airscan simple-scan system-config-printer]
    }
}

# root-only (0700): a user planning the system layer would not find it on PATH
const CUPSD = "/usr/bin/cupsd"
const PDF_QUEUE = "PDF"
const SYNC = "/usr/local/bin/printers-sync"
# after 90-anonymous-persona, which starts avahi on a home up
const DISPATCHER = "/etc/NetworkManager/dispatcher.d/95-printers-sync"
const NSSWITCH = "/etc/nsswitch.conf"
const NSSWITCH_HOSTS = "hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns"

export def system [cfg: record] {
    # cups also arrives under wsl, as a dependency of hermes-agent, where windows owns the printers
    if not ($CUPSD | path exists) or $env.FORM_FACTOR? == "wsl" { return [] }
    [
        (file-copy printers-sync.nu $SYNC --mode 755)
        (unit-file printers-sync.service)
        (file-copy printers-dispatcher.nu $DISPATCHER --mode 755)
        (step queues)
    ]
}

def queue-pdf []: nothing -> bool {
    # -v, not -p: -p also answers for a temporary destination cups discovered under the same name
    (^lpstat -v | complete | get stdout) =~ $"\(?m\)^device for ($PDF_QUEUE): "
}

# Turns on mdns host lookup, adds the PDF queue and a queue per driverless printer found now.
export def queues []: nothing -> nothing {
    # cups.socket is enabled in base/systemd, but nothing starts it at boot
    ^systemctl start cups.socket
    let nss = open --raw $NSSWITCH
    if not ($nss | str contains mdns_minimal) {
        cp $NSSWITCH $"($NSSWITCH).bak-(date now | format date '%Y%m%d')"
        $nss | str replace --regex --multiline '^hosts:.*$' $NSSWITCH_HOSTS | save --force $NSSWITCH
    }
    # the PDF queue is the first-install marker: once it exists, leave mdns discovery to the NM dispatcher on home connect
    if (queue-pdf) { return }
    ^lpadmin -p $PDF_QUEUE -v cups-pdf:/ -m CUPS-PDF_opt.ppd -E
    try { ^$SYNC } catch { log-warn "printing: some printers found over mdns got no queue, see above" }
    if (^lpstat -v | complete | get stdout) !~ ' dnssd://' {
        log-info "printing: no driverless printer queue yet, the next home connect that finds a printer adds one"
    }
    if not (queue-pdf) { error make {msg: $"printing: no ($PDF_QUEUE) queue"} }
}
