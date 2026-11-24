use module.nu *

export const meta = {
    packages: {
        pacman: [cups cups-pdf cups-pk-helper ipp-usb print-manager sane sane-airscan simple-scan system-config-printer]
    }
}

export const options = {
    # programs reading libpaper take theirs from LC_PAPER (core/locale)
    page_size: {
        type: string
        default: "A4"
        choices: [A3 A4 A5 Letter Legal]
        doc: "Default paper of every queue (PPD PageSize)"
        label: "Paper size"
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
        (file-render scripts/printers-sync.nu $SYNC {PAGE_SIZE: $cfg.page_size} --mode 755)
        (unit-file services/printers-sync.service)
        (file-copy scripts/printers-dispatcher.nu $DISPATCHER --mode 755)
        # mdns host lookup, for the printers' .local names; the rest of the file stays the package's
        (file-text $NSSWITCH (open --raw $NSSWITCH | str replace --regex --multiline '^hosts:.*$' $NSSWITCH_HOSTS))
        (step queues $cfg.page_size)
    ]
}

# The stdout of a cups client in the C locale: lpstat and lpoptions translate the lines this module parses.
def --wrapped cups-out [cmd: string, ...args: string]: nothing -> string {
    with-env {LC_ALL: C} { ^$cmd ...$args | complete | get stdout }
}

def queue-pdf []: nothing -> bool {
    # -v, not -p: -p also answers for a temporary destination cups discovered under the same name
    (cups-out lpstat -v) =~ $"\(?m\)^device for ($PDF_QUEUE): "
}

# Sets PageSize on every permanent queue whose default differs, a driverless printer often answers Letter.
def queues-page-size [page_size: string]: nothing -> nothing {
    let names = cups-out lpstat -v | parse --regex '(?m)^device for (?<name>[^:]+): ' | get name
    for name in $names {
        let sizes = cups-out lpoptions -p $name -l | lines | where $it =~ '^PageSize/'
        if ($sizes | is-empty) or ($sizes.0 | str contains $" *($page_size) ") { continue }
        if (^lpadmin -p $name -o $"PageSize=($page_size)" | complete).exit_code != 0 {
            log-warn $"printing: ($name) keeps its default paper, it takes no PageSize=($page_size)"
        }
    }
}

# Adds the PDF queue and a queue per driverless printer found now, and sets every queue's default paper.
export def queues [page_size: string]: nothing -> nothing {
    # cups.socket is enabled in base/systemd, but nothing starts it at boot
    ^systemctl start cups.socket
    # the PDF queue is the first-install marker: once it exists, leave mdns discovery to the NM dispatcher on home connect
    if (queue-pdf) { queues-page-size $page_size; return }
    ^lpadmin -p $PDF_QUEUE -v cups-pdf:/ -m CUPS-PDF_opt.ppd -E
    try { ^$SYNC } catch { log-warn "printing: some printers found over mdns got no queue, see above" }
    if (cups-out lpstat -v) !~ ' dnssd://' {
        log-info "printing: no driverless printer queue yet, the next home connect that finds a printer adds one"
    }
    if not (queue-pdf) { error make {msg: $"printing: no ($PDF_QUEUE) queue"} }
    queues-page-size $page_size
}
