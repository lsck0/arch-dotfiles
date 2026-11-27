#!/usr/bin/env -S nu --no-config-file
const SYNC = path self scripts/printers-sync.nu
const WANT_NAME = "Example_Inkjet_0A0B0C"
const WANT_URI = "dnssd://Example%20Inkjet%20%5B0A0B0C%5D._ipp._tcp.local/?uuid=00000000-0000-0000-0000-000000000001"
const WANT_UUID = "00000000-0000-0000-0000-000000000001"
# what cups keeps for an IPP Everywhere queue: the URI the dnssd one resolved to
const WANT_DEVICE = "ipp://EXAMPLE0A0B0C.local:631/ipp/print"
const LPINFO = [
    $"network ($WANT_URI)"
    "network dnssd://Example%20Inkjet%20%5B0A0B0C%5D._ipps._tcp.local/?uuid=00000000-0000-0000-0000-000000000001"
    "network dnssd://Old%20Laser._printer._tcp.local/?uuid=00000000-0000-0000-0000-000000000002"
    "network dnssd://Old%20Laser._pdl-datastream._tcp.local/?uuid=00000000-0000-0000-0000-000000000002"
    "network ipp://192.0.2.20/ipp/print"
]
const SHEBANG = "#!/usr/bin/env -S nu --no-config-file"
const STUBS = {
    lpinfo: 'def --wrapped main [...args] { print --raw (open --raw ($env.STUB_STATE | path join lpinfo.out)) }'
    lpstat: '
def --wrapped main [...args] {
    let queues = open --raw ($env.STUB_STATE | path join queues) | lines | where $it != "" | split column " " name uri
    let default = $env.STUB_STATE | path join default
    match $args.0 {
        "-v" => { $queues | each {|q| print $"device for ($q.name): ($q.uri)" } | ignore }
        "-d" => { if ($default | path exists) and (open --raw $default | str trim | is-not-empty) { print $"system default destination: (open --raw $default | str trim)" } else { print "no system default destination" } }
    }
}'
    # answers the uuid in hosts ("<uri> <uuid>" lines) for a host that is up, fails like an unresolvable name otherwise
    ipptool: '
def --wrapped main [...args] {
    let uri = $args | where $it =~ "://" | first
    let host = open --raw ($env.STUB_STATE | path join hosts) | lines | where $it != "" | split column " " uri uuid | where uri == $uri | get --optional 0
    if $host == null { print --stderr "ipptool: Unable to connect - Name or service not known"; exit 1 }
    print $"        printer-uuid \(uri\) = urn:uuid:($host.uuid)"
}'
    lpadmin: '
def --wrapped main [...args] {
    $"lpadmin ($args | str join " ")\n" | save --append ($env.STUB_STATE | path join calls)
    let at = {|flag| $args | enumerate | where item == $flag | get --optional 0.index }
    let d = do $at "-d"
    if $d != null { $"($args | get ($d + 1))\n" | save --force ($env.STUB_STATE | path join default) }
    let p = do $at "-p"
    let v = do $at "-v"
    if $p != null and $v != null {
        # cups resolves the dnssd URI of an IPP Everywhere queue, and keeps a plain -v as given
        let uri = if "everywhere" in $args { "ipp://EXAMPLE0A0B0C.local:631/ipp/print" } else { $args | get ($v + 1) }
        let name = $args | get ($p + 1)
        let queues = $env.STUB_STATE | path join queues
        open --raw $queues | lines | where $it != "" and not ($it | str starts-with $"($name) ") | append $"($name) ($uri)" | to text | save --force $queues
    }
}'
}

use std/assert

const PAGE_SIZE = "A4"

# the script as mod.nu installs it, its paper filled in; its exit code and stderr
def sync-run [work: path]: nothing -> record<exit_code: int, stderr: string> {
    let sync = $work | path join printers-sync.nu
    if not ($sync | path exists) { open --raw $SYNC | str replace --all "@PAGE_SIZE@" $PAGE_SIZE | save $sync }
    with-env {PATH: ([($work | path join bin)] ++ $env.PATH), STUB_STATE: $work} {
        ^nu --no-config-file $sync | complete | select exit_code stderr
    }
}

def main [] {
    let work = mktemp --directory
    try {
        mkdir ($work | path join bin)
        $STUBS | items {|name, body|
            let file = $work | path join bin $name
            $"($SHEBANG)\n($body)\n" | save $file
            ^chmod +x $file
        } | ignore
        $LPINFO | to text | save ($work | path join lpinfo.out)
        "" | save ($work | path join queues)
        "" | save ($work | path join calls)

        $"($WANT_DEVICE) ($WANT_UUID)\n" | save ($work | path join hosts)
        let file = {|name| open --raw ($work | path join $name) | str trim }
        let ok = {|what| let run = sync-run $work; assert equal $run.exit_code 0 $"($what) failed: ($run.stderr)"; $run.stderr }

        do $ok "first run"
        assert equal (do $file queues) $"($WANT_NAME) ($WANT_DEVICE)" "want exactly one queue"
        assert equal (do $file default) $WANT_NAME "the new queue did not become the default"
        assert ((do $file calls) | str contains "-m everywhere") "the queue is not an IPP Everywhere one"
        assert ((do $file calls) | str contains $"lpadmin -p ($WANT_NAME) -o PageSize=($PAGE_SIZE)") $"the new queue's paper is not ($PAGE_SIZE)"

        "" | save --force ($work | path join calls)
        let stderr = do $ok "rerun"
        assert equal (do $file calls) "" "rerun was not a no-op"
        assert equal $stderr "" $"rerun warned about its own queue: ($stderr)"

        # avahi renamed the printer's host: the queue's ipp:// URI no longer resolves
        "" | save --force ($work | path join hosts)
        do $ok "run with a gone host"
        assert equal (do $file calls) $"lpadmin -p ($WANT_NAME) -v ($WANT_URI)" "the queue was not moved to the dnssd URI"
        assert equal (do $file queues) $"($WANT_NAME) ($WANT_URI)" "the queue does not point at the dnssd URI"

        # a same-named queue that answers for another printer stays as it is
        $"($WANT_NAME) ($WANT_DEVICE)\n" | save --force ($work | path join queues)
        $"($WANT_DEVICE) 00000000-0000-0000-0000-0000000000ff\n" | save --force ($work | path join hosts)
        "" | save --force ($work | path join calls)
        let stderr = do $ok "run with another device"
        assert equal (do $file calls) "" "another device's queue was changed"
        assert ($stderr | str contains "exists for another device") "another device's queue was not reported"

        "" | save --force ($work | path join queues)
        "PDF\n" | save --force ($work | path join default)
        do $ok "run with a default"
        assert equal (do $file default) "PDF" "a set default was replaced"
    } catch {|e|
        rm --recursive --permanent $work
        print --stderr $e.msg
        exit 1
    }
    rm --recursive --permanent $work
    print "printers-sync.test: ok"
}
