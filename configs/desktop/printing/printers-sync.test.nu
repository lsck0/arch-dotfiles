#!/usr/bin/env -S nu --no-config-file
const SYNC = path self scripts/printers-sync.nu
const WANT_NAME = "Example_Inkjet_0A0B0C"
const WANT_URI = "dnssd://Example%20Inkjet%20%5B0A0B0C%5D._ipp._tcp.local/?uuid=00000000-0000-0000-0000-000000000001"
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
    lpadmin: '
def --wrapped main [...args] {
    $"lpadmin ($args | str join " ")\n" | save --append ($env.STUB_STATE | path join calls)
    let at = {|flag| $args | enumerate | where item == $flag | get --optional 0.index }
    let d = do $at "-d"
    if $d != null { $"($args | get ($d + 1))\n" | save --force ($env.STUB_STATE | path join default) }
    let p = do $at "-p"
    let v = do $at "-v"
    if $p != null and $v != null { $"($args | get ($p + 1)) ($args | get ($v + 1))\n" | save --append ($env.STUB_STATE | path join queues) }
}'
}

use std/assert

const PAGE_SIZE = "A4"

# the script as mod.nu installs it, its paper filled in
def sync-run [work: path]: nothing -> int {
    let sync = $work | path join printers-sync.nu
    if not ($sync | path exists) { open --raw $SYNC | str replace --all "@PAGE_SIZE@" $PAGE_SIZE | save $sync }
    with-env {PATH: ([($work | path join bin)] ++ $env.PATH), STUB_STATE: $work} {
        ^nu --no-config-file $sync | complete | get exit_code
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
        let file = {|name| open --raw ($work | path join $name) | str trim }

        assert equal (sync-run $work) 0 "first run failed"
        assert equal (do $file queues) $"($WANT_NAME) ($WANT_URI)" "want exactly one queue"
        assert equal (do $file default) $WANT_NAME "the new queue did not become the default"
        assert ((do $file calls) | str contains "-m everywhere") "the queue is not an IPP Everywhere one"
        assert ((do $file calls) | str contains $"lpadmin -p ($WANT_NAME) -o PageSize=($PAGE_SIZE)") $"the new queue's paper is not ($PAGE_SIZE)"

        "" | save --force ($work | path join calls)
        assert equal (sync-run $work) 0 "rerun failed"
        assert equal (do $file calls) "" "rerun was not a no-op"

        "" | save --force ($work | path join queues)
        "PDF\n" | save --force ($work | path join default)
        assert equal (sync-run $work) 0 "run with a default failed"
        assert equal (do $file default) "PDF" "a set default was replaced"
    } catch {|e|
        rm --recursive --permanent $work
        print --stderr $e.msg
        exit 1
    }
    rm --recursive --permanent $work
    print "printers-sync.test: ok"
}
