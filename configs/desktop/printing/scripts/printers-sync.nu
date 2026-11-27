#!/usr/bin/nu --no-config-file
# a permanent queue per driverless printer cups finds over mdns, bound to its .local name so a new lease never breaks it

const DISCOVERY_TIMEOUT_S = 10
const QUERY_TIMEOUT_S = 5
const SERVICES = [ipp ipps]
const DEFAULT_SET = "system default destination:"
# desktop/printing's page_size option, filled in when mod.nu installs this script as /usr/local/bin/printers-sync
const PAGE_SIZE = "@PAGE_SIZE@"

def warn [msg: string]: nothing -> nothing { print --stderr $"printers-sync: ($msg)" }

# The queue name of an mdns instance: "Example%20Inkjet%20%5B0A0B0C%5D" -> Example_Inkjet_0A0B0C.
def queue-name [instance: string]: nothing -> string {
    $instance | url decode | str replace --all --regex '[^A-Za-z0-9_-]+' "_" | str trim --char "_"
}

# The printer-uuid the device behind a queue's URI answers, "" when its host is gone or does not answer.
def device-uuid [uri: string]: nothing -> string {
    # timeout: ipptool keeps retrying a host that does not resolve
    ^timeout ($QUERY_TIMEOUT_S * 2) ipptool -T $QUERY_TIMEOUT_S -tv $uri get-printer-attributes.test | complete | get stdout
    | parse --regex 'printer-uuid \(uri\) = urn:uuid:(?<uuid>[0-9A-Za-z-]+)' | get --optional 0.uuid | default "" | str lowercase
}

def main []: nothing -> nothing {
    # lpstat translates the lines parsed here
    $env.LC_ALL = "C"
    let discovered = ^lpinfo --timeout $DISCOVERY_TIMEOUT_S --include-schemes dnssd -v | complete | get stdout | lines
    let existing = ^lpstat -v | complete | get stdout
    mut seen = []
    mut created = ""
    mut failed = false
    for svc in $SERVICES {
        let pattern = '^dnssd://(?<instance>[^/?]+)\._' + $svc + '\._tcp\.local/(\?uuid=(?<uuid>[0-9A-Za-z-]+))?$'
        for line in $discovered {
            let uri = $line | split row --number 2 " " | get --optional 1 | default "" | str trim
            let found = $uri | parse --regex $pattern | get --optional 0
            if $found == null { continue }
            let key = if ($found.uuid | is-empty) { $found.instance } else { $found.uuid }
            if $key in $seen { continue }
            $seen = $seen | append $key
            if ($existing | str contains $key) { continue }
            let name = queue-name $found.instance
            if ($name | is-empty) { continue }
            # lpstat -p also answers for cups' temporary destination of the same name, so only a permanent queue counts;
            # cups keeps the ipp:// URI it resolved the dnssd one to, whose .local host avahi may rename later
            let queue = $existing | parse --regex $"\(?m\)^device for ($name): \(?<uri>\\S+\)$" | get --optional 0
            if $queue != null {
                let answer = device-uuid $queue.uri
                if ($answer | is-empty) {
                    # the printer is announced under this name, but the queue's host is gone: point it at the dnssd URI
                    if (^lpadmin -p $name -v $uri | complete).exit_code == 0 {
                        warn $"($name) moved from ($queue.uri) to ($uri)"
                    } else {
                        warn $"($name) points at the gone ($queue.uri), and lpadmin did not move it to ($uri)"
                        $failed = true
                    }
                } else if ($found.uuid | is-not-empty) and $answer != ($found.uuid | str lowercase) {
                    warn $"a queue named ($name) exists for another device, not adding ($uri)"
                }
                continue
            }
            if (^lpadmin -p $name -E -v $uri -m everywhere -o printer-is-shared=false | complete).exit_code == 0 {
                warn $"added ($name) \(($uri)\)"
                # a second call: lpadmin edits PageSize in the PPD cups generated for the new queue
                if (^lpadmin -p $name -o $"PageSize=($PAGE_SIZE)" | complete).exit_code != 0 {
                    warn $"($name) keeps the printer's default paper, it takes no PageSize=($PAGE_SIZE)"
                }
                if ($created | is-empty) { $created = $name }
            } else {
                warn $"($uri) does not take an IPP Everywhere queue"
                $failed = true
            }
        }
    }
    if ($created | is-not-empty) and not ((^lpstat -d | complete | get stdout) | str contains $DEFAULT_SET) {
        if (^lpadmin -d $created | complete).exit_code != 0 { $failed = true }
    }
    if $failed { exit 1 }
}
