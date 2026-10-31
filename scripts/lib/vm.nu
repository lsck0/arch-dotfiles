# The VM test: a libvirt guest from the lsck0 iso with an answer file, watched through beacons, under the conditions
# of vm/scenarios.nuon.

use state.nu [xdg]
use platform.nu [PLATFORM_NAME_FILE]
use iso.nu [iso-signer-verify]
use ../../platforms/homelab.nu

const REPO = path self ../..
const VM_DIR = path self vm
const SCENARIOS = path self vm/scenarios.nuon
const CONNECT = "qemu:///session"
const CACHE_NAME = "vm-test"
# next to the lsck0 repo's $arch dirs on the lab's public mirror
const ISO_URL = $homelab.HOMELAB.mirror.lsck0 | str replace '$arch' "iso/archlinux-lsck0-latest-x86_64.iso"
const ANSWERS_LABEL = "LSCK0"
const ANSWERS_NAME = "lsck0.nuon"
export const USER = "luca"
const PROFILE = "luca"
const PASSWORD = "admin"
const PLATFORM = "vm"
const DISK = "/dev/vda"
# the guest's watcher port; the host side takes the first free one from there
const PORT = 8765
const PORT_SPAN = 32
const LOOPBACK = "127.0.0.1"
# passt's view for the guest: it maps the gateway to its namespace's loopback, which pasta -T forwards to the host's
const GUEST_ADDRESS = "10.0.2.15/24"
const GUEST_GATEWAY = "10.0.2.2"
const GUEST_MAC = "52:54:00:4c:53:30"
# the host's resolver, through passt and pasta; a scenario's dns replaces it
const GUEST_DNS = "10.0.2.3"
# the namespace's own link, off every cidr a scenario blocks
const NAMESPACE_ADDRESS = "10.123.0.2"
const NAMESPACE_GATEWAY = "10.123.0.1"
const NAMESPACE_PREFIX = 24
const NETDEV = "vmtest"
# a pcie.0 slot libvirt's own devices leave free, or qemu hands slot 1 to the nic before the video card
const NETDEV_SLOT = "0x10"
# libvirt session's qemu is not our child: its threads get the run's low priority by hand, everything else through this
const NICENESS = 19
const LOW_PRIORITY = $"nice -n ($NICENESS) ionice -c3"
const SOCKET_WAIT = 10sec
const FIRMWARE_DIR = "/usr/share/edk2/x64"
# secure boot firmware with an empty variable store: Setup Mode, so the install enrolls its own keys
const FIRMWARE_CODE = "OVMF_CODE.secboot.4m.fd"
const FIRMWARE_VARS = "OVMF_VARS.4m.fd"
const POLL = 15sec
const DISK_GIB = 200
const BOOTSTRAP_TIMEOUT = 1hr
const CHAIN_TIMEOUT = 12hr
const SNAPSHOT_REF = "refs/vm-test/snapshot"
const SCENARIO_ALL = "all"
const SCENARIO_SEPARATOR = ","
const HOST_LAN = "host-lan"
# base/networkmanager's homelab_subnets on the run's platform and the host's own
const HOMELAB = "homelab"
const NETWORK_MODULE = "base/networkmanager"
# the guest's resolver at home when no platform names a homelab_dns
const DNS_FALLBACK = "9.9.9.9"
const BEACON_BOOTSTRAP_OK = "bootstrap-ok"
const DOMAIN_DOWN = ["shut off" "crashed"]
const STAGES = [install config]
const STAGE_OUTCOMES = [ok failed]
# the guest end is /dev/virtio-ports/<name>: stage-report.nu writes its archive and verdict there, past any firewall
const CHANNEL_NAME = "lsck0.report"
const CHANNEL_BEACON = "beacon"
const CHANNEL_LOGS = "logs.tgz"
const STATUS_FILE = "status.json"

def --wrapped virsh [...args: string]: nothing -> string {
    ^virsh -c $CONNECT ...$args | complete | get stdout
}

def --wrapped low [...args: string]: any -> any {
    $in | ^nice -n $NICENESS ionice -c3 ...$args
}

def cache-base []: nothing -> path {
    xdg cache $CACHE_NAME
}

# The vm's cache dir, not created: a plan and a teardown write nothing.
def cache-path [name: string]: nothing -> path {
    cache-base | path join $name
}

export def cache-dir [name: string]: nothing -> path {
    let dir = cache-path $name
    mkdir $dir
    $dir
}

def scenarios-load []: nothing -> record { open $SCENARIOS }

export def vm-scenario-names []: nothing -> list<string> {
    let all = scenarios-load
    ($all.scenarios | columns) ++ ($all.presets | columns) ++ [$SCENARIO_ALL]
}

# Merges the next record's keys in, refusing a key two scenarios set to different values.
def merge-strict [what: string, merged: record, next: record]: nothing -> record {
    $next | transpose key value | reduce --fold $merged {|e, acc|
        let have = $acc | get --optional $e.key
        if $have != null and $have != $e.value {
            error make {msg: $"scenarios disagree on ($what) ($e.key): ($have | to nuon) and ($e.value | to nuon)"}
        }
        $acc | upsert $e.key $e.value
    }
}

def one-of [what: string, values: list<any>]: nothing -> any {
    let distinct = $values | uniq
    if ($distinct | length) > 1 { error make {msg: $"scenarios disagree on ($what): ($distinct | to nuon)"} }
    $distinct | get --optional 0
}

# One run's whole setup: the selected scenarios over the base one, and the platform and profile they need.
def scenario-resolve [spec: record, platform: any, profile: any]: nothing -> record {
    let all = scenarios-load
    let base = $all.scenarios | get $all.base
    let chosen = $spec.names | uniq | each {|n|
        let s = $all.scenarios | get --optional $n
        if $s == null { error make {msg: $"unknown scenario ($n), one of: (vm-scenario-names | str join ' ')"} }
        $s
    }
    let field = {|key| $chosen | each { get --optional $key } | compact }
    let networks = do $field network
    let block = $networks | each { $in.block? | default [] } | flatten | uniq
    let bad = $block | where {|b| $b not-in [$HOST_LAN $HOMELAB] and not ($b =~ '^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$') }
    if ($bad | is-not-empty) { error make {msg: $"($SCENARIOS): block ($bad | str join ' ') is no cidr, ($HOST_LAN) nor ($HOMELAB)"} }
    let required = one-of profile (do $field profile)
    if $required != null and $profile != null and $profile != $required {
        error make {msg: $"scenario ($spec.label) needs profile ($required), not ($profile)"}
    }
    let combine = {|key| do $field $key | reduce --fold {} {|r, acc| merge-strict $key $acc $r } }
    let stages = do $combine stages
    let outcome_bad = $stages | items {|s, o| if $s not-in $STAGES or $o not-in $STAGE_OUTCOMES { $"($s): ($o)" } } | compact
    if ($outcome_bad | is-not-empty) {
        error make {msg: $"($SCENARIOS): stages ($outcome_bad | str join ', '), wants ($STAGES | str join '|'): ($STAGE_OUTCOMES | str join '|')"}
    }
    {
        label: $spec.label
        scenarios: ($spec.names | uniq)
        platform: ($platform | default $spec.platform | default $PLATFORM)
        profile: ($profile | default $required | default $PROFILE)
        answers: (($base.answers? | default {}) | merge (do $combine answers))
        expect: (($base.expect? | default {}) | merge (do $combine expect))
        network: {
            block: $block
            dns: (one-of dns ($networks | each { $in.dns? } | compact))
            ipv6: (one-of ipv6 ($networks | each { $in.ipv6? } | compact) | default true)
        }
        stages: $stages
        failures_allowed: (do $field failures_allowed | flatten | uniq)
        stopped: ($all.stopped? | default {})
        usb_redirect: (do $field usb_redirect | all { $in })
        extra_packages: (do $field extra_packages | flatten | uniq)
        replace: (do $field replace | flatten)
    }
}

# The runs a --scenario value asks for: a comma list of scenarios and presets is one run, all is each of them alone.
export def vm-scenario-plan [spec: string, platform: any, profile: any]: nothing -> list<record> {
    let all = scenarios-load
    let preset = {|name, p| {label: $name, names: $p.scenarios, platform: ($p.platform? | default null)} }
    let specs = if $spec == $SCENARIO_ALL {
        let alone = $all.scenarios | columns | each {|n| {label: $n, names: [$n], platform: null} }
        $alone ++ ($all.presets | transpose name p | each {|e| do $preset $e.name $e.p })
    } else {
        let tokens = $spec | split row $SCENARIO_SEPARATOR | str trim | where $it != ""
        if ($tokens | is-empty) or $SCENARIO_ALL in $tokens and ($tokens | length) > 1 {
            error make {msg: $"--scenario takes a comma list of (vm-scenario-names | str join ' '), or ($SCENARIO_ALL) alone"}
        }
        let parts = $tokens | each {|t|
            let p = $all.presets | get --optional $t
            if $p != null { do $preset $t $p } else { {label: $t, names: [$t], platform: null} }
        }
        let platforms = $parts | each { $in.platform } | compact
        [{
            label: ($tokens | str join "+")
            names: ($parts | each { $in.names } | flatten)
            platform: (one-of "preset platform" $platforms)
        }]
    }
    $specs | each {|s| scenario-resolve $s $platform $profile }
}

# The snapshot files a run changes, read through `read` (the working tree for a plan, the snapshot index for a run).
export def vm-snapshot-edits [run: record, read: closure]: nothing -> list<record> {
    let platform_file = $"platforms/($run.platform).nuon"
    let extras = if ($run.extra_packages | is-empty) { [] } else {
        let text = do $read $platform_file
        if $text == null { error make {msg: $"extra packages need a platform file, ($platform_file) is none"} }
        let p = $text | from nuon
        [{path: $platform_file, text: ($p | upsert extra_packages (($p.extra_packages? | default []) ++ $run.extra_packages) | to nuon --indent 4)}]
    }
    let replaced = $run.replace | each {|r|
        let text = do $read $r.path
        if $text == null or not ($text =~ $r.pattern) {
            error make {msg: $"($SCENARIOS): ($r.path) has no match for '($r.pattern)', the scenario no longer applies"}
        }
        {path: $r.path, text: ($text | str replace --regex $r.pattern $r.to)}
    }
    $extras ++ $replaced
}

def host-lan-subnets []: nothing -> list<string> {
    let dev = ^ip -j -4 route show default | from json | get --optional 0.dev
    if $dev == null { error make {msg: $"($HOST_LAN): the host has no default route"} }
    ^ip -j -4 route show dev $dev scope link proto kernel | from json | get dst
}

# The homelab's subnets and resolver from base/networkmanager's options of these platforms, the first one's dns first;
# a homelab platform's unset ones are the lab's own (platforms/homelab.nu, the options' defaults).
export def vm-homelab [platforms: list<string>]: nothing -> record {
    let lab = {homelab_subnets: $homelab.HOMELAB.subnets, homelab_dns: $homelab.HOMELAB.router}
    let options = $platforms | uniq | each {|p|
        let file = $REPO | path join platforms $"($p).options.nuon"
        let set = if ($file | path exists) { open $file | get --optional $NETWORK_MODULE } else { null }
        let lab_platform = try { open ($REPO | path join platforms $"($p).nuon") | get --optional facts.homelab | default false } catch { false }
        if $lab_platform { $lab | merge ($set | default {}) } else { $set }
    } | compact
    {
        subnets: ($options | each { $in.homelab_subnets? | default [] } | flatten | uniq)
        dns: ($options | each { $in.homelab_dns? } | compact | get --optional 0)
    }
}

def host-platforms []: nothing -> list<string> {
    try { [(open --raw $PLATFORM_NAME_FILE | str trim)] | where $it != "" } catch { [] }
}

# One run's network from the host's facts (lan: its link subnets, lab: homelab subnets, home_dns: the home resolver):
# the blocked cidrs, the guest's resolver (forward: passt relays 10.0.2.3 to it) and whether the guest gets IPv6.
export def vm-network [run: record, host: record]: nothing -> record {
    let block = $run.network.block | each {|b|
        if $b == $HOST_LAN { $host.lan } else if $b == $HOMELAB { $host.lab } else { [$b] }
    } | flatten | uniq
    {
        block: $block
        dns: ($run.network.dns | default $host.home_dns | default $DNS_FALLBACK)
        forward: ($run.network.dns == null)
        ipv6: $run.network.ipv6
    }
}

# The guest's network: passt in a pasta namespace of luca's own, where the blocked cidrs are unreachable routes.
def run-network [name: string, run: record, host_port: int = $PORT]: nothing -> record {
    let dir = cache-path $name
    let lab = vm-homelab ((host-platforms) ++ [$run.platform])
    let host = {lan: (if $HOST_LAN in $run.network.block { host-lan-subnets } else { [] }), lab: $lab.subnets, home_dns: $lab.dns}
    vm-network $run $host | merge {
        host_port: $host_port
        socket: ($dir | path join passt.sock)
        pidfile: (vm-processes $name | where what == pasta | get 0.pidfile)
        log: ($dir | path join network.log)
    }
}

# passt runs as pid 1 of pasta's namespace, so only pasta writes a pidfile; passt goes by its socket.
export def vm-network-command [net: record]: nothing -> list<string> {
    let dns = if $net.forward { [-D $GUEST_DNS --dns-forward $GUEST_DNS --dns-host $net.dns] } else { [-D $net.dns] }
    let family = if $net.ipv6 { [] } else { [-4] }
    let passt = [passt -f -s $net.socket ...$family -a $GUEST_ADDRESS -g $GUEST_GATEWAY ...$dns] | str join " "
    let inner = $net.block | each { $"ip route add unreachable ($in)" } | append $"exec ($passt)" | str join " && "
    [
        ...($LOW_PRIORITY | split row " ")
        pasta --config-net -a $NAMESPACE_ADDRESS -n ($NAMESPACE_PREFIX | into string) -g $NAMESPACE_GATEWAY
        -T $"($PORT):($net.host_port)" -P $net.pidfile -- sh -c $inner
    ]
}

def network-start [name: string, net: record]: nothing -> nothing {
    network-stop $name
    cache-dir $name | ignore
    let argv = vm-network-command $net | each { $"'($in)'" } | str join " "
    ^bash -c $"($argv) > '($net.log)' 2>&1 &"
    let deadline = (date now) + $SOCKET_WAIT
    while not ($net.socket | path exists) {
        if (date now) > $deadline { error make {msg: $"passt did not come up, see ($net.log)"} }
        sleep 200ms
    }
}

# What a run leaves running outside libvirt, each by pidfile and by command line: a teardown, `dot test destroy` and
# the next run stop them, so ctrl+c (which ends only nu) leaves nothing behind for long.
export def vm-processes [name: string]: nothing -> table {
    let dir = cache-path $name
    [
        [what pidfile pattern];
        [socat ($dir | path join socat.pid) $"serve.sh ($dir | path join host)"]
        [pasta ($dir | path join pasta.pid) $"pasta .*-P ($dir | path join pasta.pid)"]
        [passt null $"passt .*-s ($dir | path join passt.sock)"]
    ]
}

def processes-stop [name: string, what: list<string>]: nothing -> nothing {
    for p in (vm-processes $name | where what in $what) {
        if $p.pidfile != null and ($p.pidfile | path exists) {
            let pid = open --raw $p.pidfile | str trim
            # a stale pidfile's pid may belong to anything by now
            let comm = try { open --raw $"/proc/($pid)/comm" | str trim } catch { "" }
            if $comm == $p.what { ^kill $pid | complete | ignore }
            rm --force $p.pidfile
        }
        ^pkill -u ($env.USER) -f $p.pattern | complete | ignore
    }
}

def network-stop [name: string]: nothing -> nothing {
    processes-stop $name [pasta passt]
    rm --force (cache-path $name | path join passt.sock)
}

# The guest's screen as a png in its cache dir.
export def screenshot [name: string]: nothing -> path {
    let png = cache-dir $name | path join screen.png
    let ppm = cache-dir $name | path join screen.ppm
    let shot = ^virsh -q -c $CONNECT screenshot $name $ppm | complete
    if $shot.exit_code != 0 { error make {msg: "screenshot failed, is the vm running?"} }
    ^magick $ppm $png
    $png
}

# Starts this vm's host server on the first free port from $PORT, after stopping a stale one of its own.
def host-start [name: string]: nothing -> record {
    host-stop $name
    let dir = cache-dir $name | path join host
    let taken = ^ss -Hltn | lines | parse --regex ':(?<port>\d+)\s' | get port | into int
    let port = $PORT..($PORT + $PORT_SPAN) | where $it not-in $taken | get --optional 0
    if $port == null { error make {msg: $"no free port from ($PORT) to ($PORT + $PORT_SPAN)"} }
    rm --recursive --force $dir
    mkdir ($dir | path join upload)
    "" | save ($dir | path join beacons)
    let pidfile = vm-processes $name | where what == socat | get 0.pidfile
    let serve = $"socat TCP-LISTEN:($port),bind=($LOOPBACK),reuseaddr,fork EXEC:'bash ($VM_DIR)/serve.sh ($dir)'"
    ^bash -c $"($LOW_PRIORITY) ($serve) > /dev/null 2>&1 & echo $! > '($pidfile)'"
    {dir: $dir, port: $port}
}

def host-stop [name: string]: nothing -> nothing {
    processes-stop $name [socat]
}

def beacons [host: record]: nothing -> list<string> {
    open --raw ($host.dir | path join beacons) | lines
}

def channel-file [name: string]: nothing -> path {
    cache-path $name | path join report.log
}

# The lines stage-report.nu wrote to the virtio channel under one tag, the tag cut off.
def channel-lines [name: string, tag: string]: nothing -> list<string> {
    let file = channel-file $name
    if not ($file | path exists) { return [] }
    open --raw $file | decode utf-8 | lines | where ($it | str starts-with $"($tag) ") | each { str substring (($tag | str length) + 1).. }
}

# The published iso, fetched once into the cache and checked against its .sha256 and the lab's iso signer; a local
# build wins via --iso.
def iso-latest []: nothing -> path {
    let iso = cache-base | path join ($ISO_URL | path basename)
    mkdir ($iso | path dirname)
    ^curl -fsSL -o $"($iso).sha256" $"($ISO_URL).sha256"
    ^curl -fsSL -o $"($iso).sig" $"($ISO_URL).sig"
    let want = open --raw $"($iso).sha256" | split row " " | first
    let sum = {|| low sha256sum $iso | split row " " | first }
    if not (($iso | path exists) and (do $sum) == $want) {
        ^curl -fL -o $iso $ISO_URL
        if (do $sum) != $want { error make {msg: $"($ISO_URL) does not match its .sha256"} }
    }
    iso-signer-verify $iso $"($iso).sig"
    $iso
}

def answers-iso [name: string, bundle: any, run: record, user: string, report: string]: nothing -> path {
    let dir = cache-dir $name | path join answers
    rm --recursive --force $dir
    mkdir $dir
    let given = {|n| $env | get --optional $n | default "" }
    let passthrough = [
        [var key value];
        [BOOTSTRAP_SERVER server ((do $given BOOTSTRAP_SERVER) == "1")]
        [BOOTSTRAP_SECURE_BOOT secure_boot (do $given BOOTSTRAP_SECURE_BOOT)]
        [BOOTSTRAP_HOSTNAME hostname (do $given BOOTSTRAP_HOSTNAME)]
        [BOOTSTRAP_GROUPS groups (do $given BOOTSTRAP_GROUPS | split row --regex '\s+' | where $it != "")]
        [BOOTSTRAP_SSH_KEY ssh_key (do $given BOOTSTRAP_SSH_KEY)]
    ] | where {|r| (do $given $r.var) != "" } | reduce --fold {} {|r, acc| $acc | insert $r.key $r.value }
    let source = if $bundle == null { {} } else {
        cp $bundle ($dir | path join snapshot.bundle)
        let lfs = snapshot-lfs $name
        if $lfs != null { cp $lfs ($dir | path join snapshot-lfs.tar) }
        {source: ({bundle: snapshot.bundle} | merge (if $lfs == null { {} } else { {lfs: snapshot-lfs.tar} }))}
    }
    {
        username: $user, profile: $run.profile, platform: $run.platform, disk: $DISK, password: $PASSWORD
        unattended: true, report: $report
    } | merge $run.answers | merge $passthrough | merge $source | to nuon | save --force ($dir | path join $ANSWERS_NAME)
    let iso = cache-dir $name | path join answers.iso
    low xorriso -as mkisofs -quiet -V $ANSWERS_LABEL -J -r -o $iso $dir
    $iso
}

export def vm-destroy [name: string]: nothing -> nothing {
    virsh destroy $name | ignore
    virsh undefine $name --nvram | ignore
    let dir = cache-path $name
    rm --force ($dir | path join disk.qcow2) ($dir | path join nvram.fd)
    network-stop $name
    host-stop $name
}

# The working tree (untracked included) over HEAD as one commit, with the run's scenario edits on top.
def snapshot-bundle [name: string, run: record]: nothing -> path {
    let index = cache-dir $name | path join snapshot.index
    rm --force $index
    ^git -C $REPO fetch -q origin master
    let tree = with-env {GIT_INDEX_FILE: $index} {
        ^git -C $REPO read-tree HEAD
        low git -C $REPO add -A
        let read = {|p| let shown = ^git -C $REPO show $":($p)" | complete; if $shown.exit_code == 0 { $shown.stdout } }
        for e in (vm-snapshot-edits $run $read) {
            let mode = ^git -C $REPO ls-files --stage -- $e.path | split row " " | first
            let blob = $e.text | ^git -C $REPO hash-object -w --stdin | str trim
            ^git -C $REPO update-index --cacheinfo $"($mode),($blob),($e.path)"
        }
        ^git -C $REPO write-tree | str trim
    }
    let commit = ^git -C $REPO commit-tree $tree -p HEAD -m "vm-test snapshot" | str trim
    ^git -C $REPO update-ref $SNAPSHOT_REF $commit
    let bundle = cache-dir $name | path join snapshot.bundle
    low git -C $REPO bundle create $bundle $SNAPSHOT_REF ^origin/master
    $bundle
}

def snapshot-lfs [name: string]: nothing -> any {
    let oids = {|ref| ^git -C $REPO lfs ls-files --long $ref | lines | each {|l| $l | split row " " | first } }
    let git_dir = ^git -C $REPO rev-parse --absolute-git-dir | str trim
    let objects = do $oids $SNAPSHOT_REF | where $it not-in (do $oids origin/master) | uniq
        | each {|oid| ["lfs" "objects" ($oid | str substring 0..1) ($oid | str substring 2..3) $oid] | path join }
        | where {|p| $git_dir | path join $p | path exists }
    let tar = cache-dir $name | path join snapshot-lfs.tar
    rm --force $tar
    if ($objects | is-empty) { return null }
    ^tar -cf $tar -C $git_dir ...$objects
    $tar
}

def virt-install-args [name: string, run: record, net: record]: nothing -> list<string> {
    let dir = cache-path $name
    let firmware = [
        $"loader=($FIRMWARE_DIR)/($FIRMWARE_CODE),loader.readonly=yes,loader.type=pflash,loader.secure=yes"
        $"nvram.template=($FIRMWARE_DIR)/($FIRMWARE_VARS),nvram=($dir | path join nvram.fd)"
    ] | str join ","
    let netdev = $"-netdev stream,id=($NETDEV),server=off,addr.type=unix,addr.path=($net.socket)"
    [
        --connect $CONNECT --name $name --memory 12288 --vcpus 8 --cpu host-passthrough
        --serial $"file,path=($dir | path join serial.log)"
        --channel $"file,path=(channel-file $name),target.type=virtio,target.name=($CHANNEL_NAME)"
        --osinfo archlinux --network none $"--qemu-commandline=($netdev) -device virtio-net-pci,netdev=($NETDEV),mac=($GUEST_MAC),bus=pcie.0,addr=($NETDEV_SLOT)"
        --graphics "spice,listen=none" --video virtio --noautoconsole
        ...(if $run.usb_redirect { [] } else { [--redirdev none] })
        --features smm.state=on --tpm none --boot $firmware
        --disk $"path=($dir | path join disk.qcow2),size=($DISK_GIB),format=qcow2,bus=virtio,discard=unmap"
    ]
}

def vm-renice [name: string]: nothing -> nothing {
    let pid = open --raw ($env.XDG_RUNTIME_DIR | path join libvirt qemu run $"($name).pid") | str trim
    for task in (ls $"/proc/($pid)/task" | get name | path basename) {
        ^renice -n $NICENESS -p $task | complete | ignore
        ^ionice -c3 -p $task | complete | ignore
    }
}

def domain-state [name: string]: nothing -> string {
    virsh domstate $name | str trim
}

def beacon-seen [name: string, host: record, tag: string]: nothing -> bool {
    $tag in (beacons $host) or $tag in (channel-lines $name $CHANNEL_BEACON)
}

# The iso's install: it beacons bootstrap-ok and powers off when done, beacons bootstrap-fail (with its log uploaded)
# when not; a power-off with neither is a crash.
def bootstrap [name: string, iso: path, host: record, bundle: any, run: record, net: record, user: string]: nothing -> nothing {
    let answers = answers-iso $name $bundle $run $user $"http://($GUEST_GATEWAY):($PORT)"
    rm --force (channel-file $name)
    ^virt-install ...(virt-install-args $name $run $net) --cdrom $iso --disk $"path=($answers),device=cdrom,readonly=on"
    vm-renice $name
    let deadline = (date now) + $BOOTSTRAP_TIMEOUT
    while (domain-state $name) not-in $DOMAIN_DOWN {
        if "bootstrap-fail" in (beacons $host) {
            error make {msg: $"the iso's install failed, see ($host.dir)/upload/bootstrap.log"}
        }
        if (date now) > $deadline { error make {msg: $"the iso's install still running after ($BOOTSTRAP_TIMEOUT), see `dot test shot`"} }
        sleep $POLL
    }
    if not (beacon-seen $name $host $BEACON_BOOTSTRAP_OK) {
        let serial = cache-path $name | path join serial.log
        error make {msg: $"the iso's install went (domain-state $name) without ($BEACON_BOOTSTRAP_OK), see ($serial)"}
    }
    virsh start $name | ignore
    vm-renice $name
}

# Waits for the chain's own report: a beacon per stage, then chain-done (or chain-fail) once its logs are uploaded,
# over http or, when the guest's firewall cuts that, over the virtio channel. A guest down with no verdict crashed.
def await-chain [name: string, host: record, logs: path]: nothing -> path {
    let start = date now
    mut seen = []
    mut verdicts = []
    while "chain-done" not-in ($seen ++ $verdicts) and "chain-fail" not-in ($seen ++ $verdicts) {
        if (date now) > ($start + $CHAIN_TIMEOUT) { error make {msg: $"no chain-done after ($CHAIN_TIMEOUT), see `dot test shot`"} }
        sleep $POLL
        # read before the beacons: a verdict sent just before a power-off still counts
        let state = domain-state $name
        let now = beacons $host
        for b in ($now | skip ($seen | length)) { print $"dot test: ($b) after ((date now) - $start)" }
        $seen = $now
        $verdicts = channel-lines $name $CHANNEL_BEACON
        let decided = "chain-done" in ($seen ++ $verdicts) or "chain-fail" in ($seen ++ $verdicts)
        if not $decided and $state in $DOMAIN_DOWN {
            let serial = cache-path $name | path join serial.log
            error make {msg: $"the guest went ($state) mid-chain with no verdict, see ($serial)"}
        }
    }
    let tgz = $host.dir | path join upload logs.tgz
    if not ($tgz | path exists) {
        let sent = channel-lines $name $CHANNEL_LOGS | where $it != "" | get --optional 0
        if $sent != null { $sent | decode base64 | save --force --raw $tgz }
    }
    if not ($tgz | path exists) {
        let failed = "chain-fail" in ($seen ++ $verdicts)
        error make {msg: (if $failed { "the chain failed before uploading its logs, see `dot test shot`" } else { "chain-done without a log upload" })}
    }
    rm --recursive --force $logs
    mkdir $logs
    ^tar -xzf $tgz -C $logs
    $logs
}

def invariants []: nothing -> table {
    open --raw ($REPO | path join scripts lib invariants.txt) | lines | where {|l| ($l | str trim | is-not-empty) and not ($l | str starts-with "#") }
    | parse --regex '^(?<key>\S+)\s+(?<want>\S+)\s+(?<where>\S+)\s+(?<probe>.*)$'
}

# Every problem in the reported logs, and notes that do not fail the run. A chain stopped before config (stage-report's
# chain_stopped, install-stop's marker) passes with a banner naming the way back online, every disarm row at its value
# and the rows of `stopped` at theirs; otherwise each stage ends as the scenario's stages say (ok by default), no FAILURES.* line but the
# failures_allowed ones, and no error in dot status unless every failure line was allowed.
export def vm-verify [logs: path, run: record]: nothing -> record {
    let state = open --raw ($logs | path join verify.log) | lines | where ($it | str contains "=") | parse "{key}={value}" | reduce --fold {} {|r, acc| $acc | upsert $r.key $r.value }
    let stopped = $state.chain_stopped? == "yes"
    let wanted = invariants | where want != "any" | reduce --fold {backup_roundtrip: ok} {|i, acc| $acc | insert $i.key $i.want }
        | merge $run.expect | merge (if $stopped { $run.stopped } else { {} })
    let facts = $wanted | items {|key, want|
        let got = $state | get --optional $key
        if $want != "any" and $got != $want { $"($key)=($got), expected ($want)" }
    } | compact
    let escape = ($state.issue_escape? == "yes")
    let banner = if $stopped and not $escape { ["the chain stopped before config with no banner naming a command to get online"] } else { [] }
    let reach = if $state.mirror_reachable? == "yes" or $escape { [] } else { ["no package mirror reachable and no banner names a command to get online"] }
    let lines = glob ($logs | path join "FAILURES.*") | sort | each {|f|
        open --raw $f | lines | where ($it | str trim) != "" | each {|l| {file: ($f | path basename), line: $l} }
    } | flatten
    let allowed = $lines | where {|l| $run.failures_allowed | any {|p| $l.line =~ $p } }
    let unexpected = $lines | where {|l| $l not-in $allowed } | each { $"($in.file): ($in.line)" }
    let stage_log = try { open --raw ($logs | path join stage.log) } catch { "" }
    let stages = if $stopped { [] } else {
        $STAGES | each {|s| {stage: $s, want: ($run.stages | get --optional $s | default ok)} }
        | where {|s| not ($stage_log | str contains $"($s.stage): ($s.want)") }
        | each { $"stage ($in.stage) did not end ($in.want), see ($in.stage).log" }
    }
    let status = try { open ($logs | path join $STATUS_FILE) } catch { null }
    let errors = if $status == null { [$"no ($STATUS_FILE) from dot status --json"] } else if $status.errors > 0 { [$"dot status: ($status.errors) errors in the last run ($status.last_run)"] } else { [] }
    let errors_allowed = ($allowed | is-not-empty) and ($unexpected | is-empty) and $status != null
    let checks = if $status == null { [] } else { $status.checks | where level == "FAIL" | each { $"dot status: ($in.check): ($in.text)" } }
    let soft = $unexpected ++ (if $errors_allowed { [] } else { $errors })
    let allowed_notes = ($allowed | each { $"allowed: ($in.file): ($in.line)" }) ++ (if $errors_allowed { $errors } else { [] })
    {
        problems: ($facts ++ $banner ++ $reach ++ $stages ++ (if $stopped { [] } else { $soft }))
        notes: ((if $stopped { ["the chain stopped before config with its banner"] ++ $soft } else { [] }) ++ $allowed_notes ++ $checks)
    }
}

# A dry run's lines: the plan, the network, virt-install and the snapshot edits, with nothing written.
export def vm-plan-lines [run: record, name: string]: nothing -> list<string> {
    let net = run-network $name $run
    let read = {|p| let f = $REPO | path join $p; if ($f | path exists) { open --raw $f } else { null } }
    [
        $"dot test: plan ($run.label): ($run | reject label | to nuon)"
        $"dot test: network ((vm-network-command $net) | str join ' ')"
        $"dot test: virt-install ((virt-install-args $name $run $net) | str join ' ')"
        ...(vm-snapshot-edits $run $read | each { $"dot test: snapshot edits ($in.path)" })
    ]
}

def keep-hint [name: string]: nothing -> string {
    $"dot test: the vm stays for inspection, remove it with: dot test destroy --name ($name)"
}

# Installs a fresh vm through the whole unattended chain under one run's scenarios and verifies it; a pass destroys it.
def vm-run [name: string, iso: path, run: record, user: string, master: bool]: nothing -> nothing {
    print $"dot test: run ($run.label) on ($run.platform) as ($run.profile)"
    vm-destroy $name
    let logs = try {
        let host = host-start $name
        let net = run-network $name $run $host.port
        network-start $name $net
        let bundle = if $master { null } else { snapshot-bundle $name $run }
        bootstrap $name $iso $host $bundle $run $net $user
        await-chain $name $host (cache-dir $name | path join logs $run.label)
    } catch {|e|
        host-stop $name
        network-stop $name
        print --stderr (keep-hint $name)
        error make {msg: $e.msg}
    }
    host-stop $name
    network-stop $name
    print $"dot test: logs in ($logs)"
    let verdict = vm-verify $logs $run
    for n in $verdict.notes { print $"dot test: note: ($n)" }
    if ($verdict.problems | is-not-empty) {
        print --stderr (keep-hint $name)
        error make {msg: ($verdict.problems | str join "\n")}
    }
    vm-destroy $name
    print $"dot test: ($run.label): chain succeeded"
}

# The runs `scenario` names, one fresh vm each; `master` takes GitHub master, not a snapshot; `dry` prints the plan.
export def vm-test [name: string, iso: any, scenario: string, platform: any, profile: any, user: string, master: bool, dry: bool]: nothing -> nothing {
    let runs = vm-scenario-plan $scenario $platform $profile
    let edited = $runs | where { ($in.extra_packages | is-not-empty) or ($in.replace | is-not-empty) } | get label
    if $master and ($edited | is-not-empty) { error make {msg: $"--master has no snapshot to edit for ($edited | str join ' ')"} }
    if $dry { for r in $runs { vm-plan-lines $r $name | each { print $in } | ignore }; return }
    for t in [virt-install virsh socat xorriso curl passt pasta] {
        if (which $t | is-empty) { error make {msg: $"($t) missing"} }
    }
    let iso = if $iso == null { iso-latest } else { $iso }
    if not ($iso | path exists) { error make {msg: $"no iso at ($iso)"} }
    if ($runs | length) == 1 { vm-run $name $iso $runs.0 $user $master; return }
    let results = $runs | each {|r|
        let problem = try { vm-run $name $iso $r $user $master; null } catch {|e| $e.msg }
        if $problem != null { print --stderr $"dot test: ($r.label) failed:\n($problem)" }
        {label: $r.label, problem: $problem}
    }
    let failed = $results | where problem != null
    for r in $results { print $"dot test: ($r.label): (if $r.problem == null { 'ok' } else { 'failed' })" }
    if ($failed | is-not-empty) { error make {msg: $"($failed | length) of ($results | length) runs failed: ($failed | get label | str join ' ')"} }
}
