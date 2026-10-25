# The end-to-end VM test behind `dot test`: a libvirt guest installed from the lsck0 iso with an answer file, watched
# through beacons and uploads to a socat server on the host; the guest's chain reports its own verdict at the end.

const REPO = path self ../..
const VM_DIR = path self vm
const CONNECT = "qemu:///system"
const POOL = "default"
const POOL_DIR = "/var/lib/libvirt/images"
const CONSOLE_DIR = "/var/log/libvirt/qemu"
const ISO_VOLUME = "vm-test-archlinux-lsck0.iso"
const ISO_URL = "https://mirror.lsck0.dev/iso/archlinux-lsck0-latest-x86_64.iso"
const ANSWERS_LABEL = "LSCK0"
const ANSWERS_NAME = "lsck0.nuon"
export const USER = "luca"
export const PROFILE = "luca"
const PASSWORD = "admin"
export const PLATFORM = "vm"
const DISK = "/dev/vda"
const PORT = 8765
const REPORT_URL = "http://10.0.2.2:8765"
const POLL = 15sec
const DISK_GIB = 200
const BOOTSTRAP_TIMEOUT = 1hr
const CHAIN_TIMEOUT = 12hr
const SNAPSHOT_REF = "refs/vm-test/snapshot"
const SUDO_KEEPALIVE = 50sec

def --wrapped virsh [...args: string]: nothing -> string {
    ^sudo virsh -c $CONNECT ...$args | complete | get stdout
}

export def cache-dir [name: string]: nothing -> path {
    let dir = $nu.home-dir | path join .cache vm-test $name
    mkdir $dir
    $dir
}

def sudo-keepalive []: nothing -> nothing {
    ^sudo -v
    job spawn { loop { "" | ^sudo -n true | complete | ignore; sleep $SUDO_KEEPALIVE } } | ignore
}

# The guest's screen as a png in its cache dir, streamed through stdout so root's virsh writes no file there.
export def screenshot [name: string]: nothing -> path {
    let png = cache-dir $name | path join screen.png
    let ppm = cache-dir $name | path join screen.ppm
    let shot = ^sudo virsh -q -c $CONNECT screenshot $name /dev/stdout | complete
    if $shot.exit_code != 0 { error make {msg: "screenshot failed, is the vm running?"} }
    $shot.stdout | save --force --raw $ppm
    ^magick $ppm $png
    $png
}

# Starts the host server on $PORT for this vm, killing a stale one of ours; any other holder is an error.
def host-start [name: string]: nothing -> record {
    let holders = ^ss -Hltnp $"sport = :($PORT)" | parse --regex 'pid=(?<pid>\d+)' | get pid | uniq
    for pid in $holders {
        let cmdline = try { open --raw $"/proc/($pid)/cmdline" | str replace --all (char nul) " " } catch { "" }
        if not ($cmdline | str contains $"($VM_DIR)/serve.sh") {
            error make {msg: $"port ($PORT) is taken: ss -ltnp 'sport = :($PORT)'"}
        }
        ^kill $pid
    }
    if ($holders | is-not-empty) { sleep 500ms }
    let dir = cache-dir $name | path join host
    rm --recursive --force $dir
    mkdir ($dir | path join upload)
    "" | save ($dir | path join beacons)
    let pid = ^bash -c $"socat TCP-LISTEN:($PORT),bind=127.0.0.1,reuseaddr,fork EXEC:'bash ($VM_DIR)/serve.sh ($dir)' > /dev/null 2>&1 & echo $!" | str trim
    {dir: $dir, pid: $pid, read: 0}
}

def host-stop [host: record]: nothing -> nothing {
    ^kill $host.pid | complete | ignore
}

def beacons [host: record]: nothing -> list<string> {
    open --raw ($host.dir | path join beacons) | lines
}

def pool-iso [iso: path, volume: string, --fresh]: nothing -> string {
    if $POOL not-in (virsh pool-list --all --name | lines | str trim) {
        virsh pool-define-as $POOL dir --target $POOL_DIR | ignore
        virsh pool-build $POOL | ignore
        virsh pool-autostart $POOL | ignore
    }
    if not (virsh pool-info $POOL | str contains running) { virsh pool-start $POOL | ignore }
    let size = ls $iso | get 0.size | into int | into string
    # the uploaded iso's checksum: a new latest build of the same size still replaces the volume
    let stamp = $nu.home-dir | path join .cache vm-test $"($volume).sha256"
    let sum = open --raw $iso | hash sha256
    let current = try { open --raw $stamp | str trim } catch { "" }
    if $fresh or $current != $sum or not (virsh vol-info --pool $POOL $volume --bytes | str contains $size) {
        virsh vol-delete --pool $POOL $volume | ignore
        virsh vol-create-as $POOL $volume $size --format raw | ignore
        virsh vol-upload --pool $POOL $volume $iso | ignore
        mkdir ($stamp | path dirname)
        $"($sum)\n" | save --force $stamp
    }
    virsh vol-path --pool $POOL $volume | str trim
}

# The published iso, fetched once into the cache and checked against its .sha256; a local build wins via --iso.
def iso-latest []: nothing -> path {
    let iso = $nu.home-dir | path join .cache vm-test ($ISO_URL | path basename)
    mkdir ($iso | path dirname)
    ^curl -fsSL -o $"($iso).sha256" $"($ISO_URL).sha256"
    let want = open --raw $"($iso).sha256" | split row " " | first
    let sum = {|| ^sha256sum $iso | split row " " | first }
    if not (($iso | path exists) and (do $sum) == $want) {
        ^curl -fL -o $iso $ISO_URL
        if (do $sum) != $want { error make {msg: $"($ISO_URL) does not match its .sha256"} }
    }
    $iso
}

def answers-volume [name: string]: nothing -> string { $"vm-test-($name)-answers.iso" }

def answers-iso [name: string, bundle: any, platform: string, user: string, profile: string]: nothing -> path {
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
        username: $user, profile: $profile, platform: $platform, disk: $DISK, password: $PASSWORD, unattended: true
        report: $REPORT_URL
    } | merge $passthrough | merge $source | to nuon | save --force ($dir | path join $ANSWERS_NAME)
    let iso = cache-dir $name | path join answers.iso
    ^xorriso -as mkisofs -quiet -V $ANSWERS_LABEL -J -r -o $iso $dir
    $iso
}

export def vm-destroy [name: string]: nothing -> nothing {
    virsh destroy $name | ignore
    virsh undefine $name --nvram --storage vda | ignore
    virsh vol-delete --pool $POOL (answers-volume $name) | ignore
}

def snapshot-bundle [name: string]: nothing -> path {
    let index = cache-dir $name | path join snapshot.index
    rm --force $index
    ^git -C $REPO fetch -q origin master
    let tree = with-env {GIT_INDEX_FILE: $index} {
        ^git -C $REPO read-tree HEAD
        ^git -C $REPO add -A
        ^git -C $REPO write-tree | str trim
    }
    let commit = ^git -C $REPO commit-tree $tree -p HEAD -m "vm-test snapshot" | str trim
    ^git -C $REPO update-ref $SNAPSHOT_REF $commit
    let bundle = cache-dir $name | path join snapshot.bundle
    ^git -C $REPO bundle create $bundle $SNAPSHOT_REF ^origin/master
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

# The iso's install: the guest powers off when done, beacons bootstrap-fail (with its log uploaded) when not.
def bootstrap [name: string, iso: path, host: record, bundle: any, platform: string, user: string, profile: string]: nothing -> nothing {
    vm-destroy $name
    let cdrom = pool-iso $iso $ISO_VOLUME
    let answers = pool-iso (answers-iso $name $bundle $platform $user $profile) (answers-volume $name) --fresh
    let console = $CONSOLE_DIR | path join $"($name)-serial.log"
    (^sudo virt-install --connect $CONNECT --name $name --memory 12288 --vcpus 8 --cpu host-passthrough
        --serial $"file,path=($console)" --disk $"pool=($POOL),size=($DISK_GIB),format=qcow2,bus=virtio,discard=unmap"
        --cdrom $cdrom --disk $"path=($answers),device=cdrom,readonly=on"
        --osinfo archlinux --network user,model=virtio --graphics spice --video virtio --noautoconsole
        --features smm.state=on
        --boot "uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=no")
    let deadline = (date now) + $BOOTSTRAP_TIMEOUT
    while (virsh domstate $name | str trim) != "shut off" {
        if "bootstrap-fail" in (beacons $host) {
            error make {msg: $"the iso's install failed, see ($host.dir)/upload/bootstrap.log"}
        }
        if (date now) > $deadline { error make {msg: $"the iso's install still running after ($BOOTSTRAP_TIMEOUT), see `dot test shot`"} }
        sleep $POLL
    }
    virsh start $name | ignore
}

# Waits for the chain's own report: a beacon per stage, then chain-done (or chain-fail) once its logs are uploaded.
def await-chain [name: string, host: record]: nothing -> path {
    let start = date now
    mut seen = []
    while "chain-done" not-in $seen and "chain-fail" not-in $seen {
        if (date now) > ($start + $CHAIN_TIMEOUT) { error make {msg: $"no chain-done after ($CHAIN_TIMEOUT), see `dot test shot`"} }
        sleep $POLL
        let now = beacons $host
        for b in ($now | skip ($seen | length)) { print $"dot test: ($b) after ((date now) - $start)" }
        $seen = $now
    }
    let tgz = $host.dir | path join upload logs.tgz
    if not ($tgz | path exists) {
        error make {msg: (if "chain-fail" in $seen { "the chain failed before uploading its logs, see `dot test shot`" } else { "chain-done without a log upload" })}
    }
    let logs = cache-dir $name | path join logs
    rm --recursive --force $logs
    mkdir $logs
    ^tar -xzf $tgz -C $logs
    $logs
}

def invariants []: nothing -> table {
    open --raw ($REPO | path join scripts lib invariants.txt) | lines | where {|l| ($l | str trim | is-not-empty) and not ($l | str starts-with "#") }
    | parse --regex '^(?<key>\S+)\s+(?<want>\S+)\s+(?<where>\S+)\s+(?<probe>.*)$'
}

# Every problem in the reported logs: invariants off their wanted value, non-empty FAILURES files, stages not ok.
def verify [logs: path]: nothing -> list<string> {
    let state = open --raw ($logs | path join verify.log) | lines | where ($it | str contains "=") | parse "{key}={value}" | reduce --fold {} {|r, acc| $acc | upsert $r.key $r.value }
    let expected = invariants | reduce --fold {backup_roundtrip: ok} {|i, acc| $acc | insert $i.key $i.want }
    let facts = $expected | items {|key, want| let got = $state | get --optional $key; if $got != $want { $"($key)=($got), expected ($want)" } } | compact
    let failures = glob ($logs | path join "FAILURES.*") | sort | where { open --raw $in | str trim | is-not-empty } | each {|f| $"($f | path basename):\n(open --raw $f | str trim --right)" }
    let stage_log = try { open --raw ($logs | path join stage.log) } catch { "" }
    let stages = [install config] | where {|s| not ($stage_log | str contains $"($s): ok") } | each { $"stage ($in) did not finish ok, see ($in).log" }
    $facts ++ $failures ++ $stages
}

# Installs a fresh vm through the whole unattended chain and verifies it; `master` takes GitHub master, not a snapshot.
export def vm-run [name: string, iso: any, platform: string, user: string, profile: string, master: bool]: nothing -> nothing {
    for t in [virt-install virsh socat xorriso curl] {
        if (which $t | is-empty) { error make {msg: $"($t) missing"} }
    }
    let iso = if $iso == null { iso-latest } else { $iso }
    if not ($iso | path exists) { error make {msg: $"no iso at ($iso)"} }
    sudo-keepalive
    let host = host-start $name
    bootstrap $name $iso $host (if $master { null } else { snapshot-bundle $name }) $platform $user $profile
    let logs = await-chain $name $host
    host-stop $host
    print $"dot test: logs in ($logs)"
    let problems = verify $logs
    if ($problems | is-not-empty) { error make {msg: ($problems | str join "\n")} }
    print "dot test: chain succeeded"
}
