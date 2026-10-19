#!/usr/bin/nu --no-config-file
# a permanent queue per driverless printer cups finds over mdns, bound to its .local name so a new lease never breaks it

# the dnssd backend browses this long; mdns answers come within a second or two
const DISCOVERY_TIMEOUT_S = 10
# an AirPrint printer advertises both: one queue, on plain ipp
const SERVICES = [ipp ipps]
const DEFAULT_SET = "system default destination:"

def warn [msg: string]: nothing -> nothing { print --stderr $"printers-sync: ($msg)" }

# "HP%20ENVY%205640%20series%20%5BB8A730%5D" -> HP_ENVY_5640_series_B8A730
def queue-name [instance: string]: nothing -> string {
    $instance | url decode | str replace --all --regex '[^A-Za-z0-9_-]+' "_" | str trim --char "_"
}

def main []: nothing -> nothing {
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
            # lpstat -p also answers for cups' temporary destination of the same name, so only a permanent queue counts
            if ($existing | str contains $"device for ($name): ") {
                warn $"a queue named ($name) exists for another device, not adding ($uri)"
                continue
            }
            if (^lpadmin -p $name -E -v $uri -m everywhere -o printer-is-shared=false | complete).exit_code == 0 {
                warn $"added ($name) \(($uri)\)"
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
