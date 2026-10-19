const REPO = path self ../..
const VM_DIR = path self vm
const REPO_URL = "https://github.com/lsck0/arch-dotfiles.git"
# gnome-boxes saves every session vm when it quits, which stalls a run
const CONNECT = "qemu:///system"
const POOL = "default"
const POOL_DIR = "/var/lib/libvirt/images"
const CONSOLE_DIR = "/var/log/libvirt/qemu"
const ISO_VOLUME = "vm-test-archlinux.iso"
# the lsck0 iso (dot internal iso) runs its installer on its own and reads lsck0.nuon from a medium labelled LSCK0
const LSCK0_ISO_LABEL = "ARCH_LSCK0_"
const LSCK0_VOLUME = "vm-test-archlinux-lsck0.iso"
const ANSWERS_LABEL = "LSCK0"
const ANSWERS_NAME = "lsck0.nuon"
const LSCK0_FAILED = "install: failed"
export const USER = "luca"
export const PROFILE = "luca"
const PASSWORD = "admin"
export const PLATFORM = "test-vm"
const BOOTSTRAP_PASSTHROUGH = [BOOTSTRAP_SERVER BOOTSTRAP_SECURE_BOOT BOOTSTRAP_HOSTNAME BOOTSTRAP_GROUPS BOOTSTRAP_SSH_KEY]
const DISK = "/dev/vda"
const PORT = 8765
const HOST = "10.0.2.2:8765"
const POLL = 15sec
const DISK_GIB = 200
const BOOTSTRAP_TIMEOUT = 1hr
const CHAIN_TIMEOUT = 12hr
export const BOOT_TIMEOUT = 5min
const LOGIN_ATTEMPTS = 3
# tty1 carries the chain's console; ly takes it only once the chain is done (desktop/ly stage.conf)
const LOGIN_TTY = 3
const SNAPSHOT_REF = "refs/vm-test/snapshot"
const KEY_HOLD_MS = 10
# each key is a sudo virsh call; the guest console drops keys sent faster
const KEY_GAP = 30ms
# well under sudo's 5 min timestamp
const SUDO_KEEPALIVE = 50sec
const MODIFIERS = [shift shift_r ctrl ctrl_r alt alt_r]
const DRILL_STEP_TIMEOUT = 1hr
const DRILL_SETTLE = 30sec
const DRILL_VALUE = '^[A-Za-z0-9._:+-]+$'
const UPLOAD_TIMEOUT = 5min
const KEYS_US = {
    " ": spc "-": minus ".": dot "/": slash ":": shift-semicolon ";": semicolon "$": shift-4 "(": shift-9 ")": shift-0
    "*": shift-8 "_": shift-minus "=": equal ">": shift-dot "<": shift-comma "'": apostrophe "\"": shift-apostrophe
    "\n": ret ",": comma "&": shift-7 "|": shift-backslash "~": shift-grave_accent "@": shift-2 "%": shift-5 "#": shift-3
    "!": shift-1 "?": shift-slash "\\": backslash "+": shift-equal "[": bracket_left "]": bracket_right
    "{": shift-bracket_left "}": shift-bracket_right
}
const KEYS_DE = {
    " ": spc "-": slash ".": dot "/": shift-7 ":": shift-dot ";": shift-comma "$": shift-4 "(": shift-8 ")": shift-9
    "*": shift-bracket_right "_": shift-slash "=": shift-0 ">": shift-less "<": less "'": shift-backslash "\"": shift-2
    "\n": ret ",": comma "&": shift-6 "|": alt_r-less "~": alt_r-bracket_right "@": alt_r-q "%": shift-5 "#": backslash
    "!": shift-1 "?": shift-minus "\\": alt_r-minus "+": bracket_right "[": alt_r-8 "]": alt_r-9 "{": alt_r-7 "}": alt_r-0
}

def --wrapped virsh [...args: string]: nothing -> string {
    ^sudo virsh -c $CONNECT ...$args | complete | get stdout
}

export def cache-dir [name: string]: nothing -> path {
    let dir = $nu.home-dir | path join .cache vm-test $name
    mkdir $dir
    $dir
}

# kept warm off the tty so it never races a foreground sudo's raw-mode switch
export def sudo-keepalive []: nothing -> nothing {
    ^sudo -v
    job spawn { loop { "" | ^sudo -n true | complete | ignore; sleep $SUDO_KEEPALIVE } } | ignore
}

# streamed through stdout, so root's virsh never leaves a root-owned file in the user's cache
export def screenshot [name: string]: nothing -> path {
    let png = cache-dir $name | path join screen.png
    let ppm = cache-dir $name | path join screen.ppm
    let shot = ^sudo virsh -q -c $CONNECT screenshot $name /dev/stdout | complete
    if $shot.exit_code != 0 { error make {msg: "screenshot failed, is the vm running?"} }
    $shot.stdout | save --force --raw $ppm
    ^magick $ppm $png
    $png
}

def screen-text [name: string]: nothing -> string {
    let ppm = cache-dir $name | path join screen.ppm
    let shot = ^sudo virsh -q -c $CONNECT screenshot $name /dev/stdout | complete
    if $shot.exit_code != 0 { return "" }
    $shot.stdout | save --force --raw $ppm
    ^tesseract $ppm - | complete | get stdout
}

def wait-screen [name: string, needles: list<string>, timeout: duration]: nothing -> any {
    let deadline = (date now) + $timeout
    while (date now) < $deadline {
        let text = screen-text $name
        let found = $needles | where {|n| $text | str contains $n } | get --optional 0
        if $found != null { return $found }
        sleep $POLL
    }
    error make {msg: $"none of ($needles | str join ', ') on screen after ($timeout), see `dot test shot`"}
}

def key-for [ch: string, layout: string]: nothing -> string {
    let table = if $layout == "de" { $KEYS_DE } else { $KEYS_US }
    if $ch in $table { return ($table | get $ch) }
    if $ch =~ '^[0-9]$' { return $ch }
    if not ($ch =~ '^[A-Za-z]$') { error make {msg: $"no key for ($ch | to nuon) on layout ($layout)"} }
    let swapped = if $layout == "de" { {y: z, z: y, Y: Z, Z: Y} | get --optional $ch | default $ch } else { $ch }
    $"(if $swapped =~ '[A-Z]' { 'shift-' } else { '' })($swapped | str lowercase)"
}

# a held key outlasting one virsh call would overlap the next
export def type-text [name: string, text: string, layout: string]: nothing -> nothing {
    let keys = $text | split chars | each {|c| key-for $c $layout }
    for k in ($keys ++ $MODIFIERS) {
        virsh qemu-monitor-command $name --hmp $"sendkey ($k) ($KEY_HOLD_MS)" | ignore
        sleep $KEY_GAP
    }
}

def clear-line [name: string]: nothing -> nothing {
    virsh qemu-monitor-command $name --hmp "sendkey ctrl-u" | ignore
}

export def host-start [name: string, upload_to: path]: nothing -> record {
    # socat's bind error goes nowhere and the guest's curl would hang on another listener
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
    mkdir ($dir | path join step) ($dir | path join file)
    "" | save ($dir | path join beacons)
    "0" | save ($dir | path join beacons.read)
    $upload_to | save ($dir | path join upload-to)
    let pid = ^bash -c $"socat TCP-LISTEN:($PORT),bind=127.0.0.1,reuseaddr,fork EXEC:'bash ($VM_DIR)/serve.sh ($dir)' > /dev/null 2>&1 & echo $!" | str trim
    {dir: $dir, pid: $pid}
}

export def host-stop [host: record]: nothing -> nothing {
    ^kill $host.pid | complete | ignore
}

def host-upload-to [host: record, path: path]: nothing -> nothing {
    $path | save --force ($host.dir | path join upload-to)
    rm --force ($host.dir | path join uploaded)
}

def host-uploaded [host: record, timeout: duration]: nothing -> bool {
    let deadline = (date now) + $timeout
    while (date now) < $deadline {
        if ($host.dir | path join uploaded | path exists) { return true }
        sleep 1sec
    }
    false
}

def unread [host: record]: nothing -> list<string> {
    let read = open --raw ($host.dir | path join beacons.read) | into int
    open --raw ($host.dir | path join beacons) | lines | skip $read
}

def mark-read [host: record, n: int]: nothing -> nothing {
    let read = open --raw ($host.dir | path join beacons.read) | into int
    $read + $n | into string | save --force ($host.dir | path join beacons.read)
}

# drops older unrelated beacons; null on timeout
export def beacon [host: record, prefix: string, timeout: duration]: nothing -> any {
    let deadline = (date now) + $timeout
    while (date now) < $deadline {
        let new = unread $host
        let at = $new | enumerate | where {|b| $b.item | str starts-with $prefix } | get --optional 0
        if $at != null {
            mark-read $host ($at.index + 1)
            return $at.item
        }
        mark-read $host ($new | length)
        sleep 1sec
    }
    null
}

def drain [host: record]: nothing -> list<string> {
    let new = unread $host
    mark-read $host ($new | length)
    $new
}

def beacon-cmd [tag: string]: nothing -> string { $"curl -s ($HOST)/beacon/($tag)" }

# sendkey garbles long lines, so type one short line that fetches the served script
def run-step [name: string, host: record, step: string, script: string, layout: string]: nothing -> nothing {
    $script | save --force ($host.dir | path join step $step)
    type-text $name $"curl -so /tmp/($step) ($HOST)/step/($step) && bash /tmp/($step)\n" $layout
}

# qemu in the system pool cannot read the home dir
def pool-iso [iso: path, volume: string, --fresh]: nothing -> string {
    if $POOL not-in (virsh pool-list --all --name | lines | str trim) {
        virsh pool-define-as $POOL dir --target $POOL_DIR | ignore
        virsh pool-build $POOL | ignore
        virsh pool-autostart $POOL | ignore
    }
    if not (virsh pool-info $POOL | str contains running) { virsh pool-start $POOL | ignore }
    let size = ls $iso | get 0.size | into int | into string
    if $fresh or not (virsh vol-info --pool $POOL $volume --bytes | str contains $size) {
        virsh vol-delete --pool $POOL $volume | ignore
        virsh vol-create-as $POOL $volume $size --format raw | ignore
        virsh vol-upload --pool $POOL $volume $iso | ignore
    }
    virsh vol-path --pool $POOL $volume | str trim
}

def iso-is-lsck0 [iso: path]: nothing -> bool {
    ^blkid -p -s LABEL -o value $iso | complete | get stdout | str trim | str starts-with $LSCK0_ISO_LABEL
}

def answers-volume [name: string]: nothing -> string { $"vm-test-($name)-answers.iso" }

# the same answers the typed path passes as env, as the lsck0 iso's answer file on a second cd
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
    {username: $user, profile: $profile, platform: $platform, disk: $DISK, password: $PASSWORD, unattended: true}
    | merge $passthrough | merge $source | to nuon | save --force ($dir | path join $ANSWERS_NAME)
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

# lfs objects the snapshot points at but GitHub may not have yet (a rebuilt firmware, a new image), else lfs pull fails
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

# nothing typed: the iso's installer reads the answers, its failure line stays on tty1
def lsck0-await [name: string]: nothing -> nothing {
    let deadline = (date now) + $BOOTSTRAP_TIMEOUT
    while (virsh domstate $name | str trim) != "shut off" {
        if (screen-text $name | str contains $LSCK0_FAILED) { error make {msg: "the lsck0 iso's install failed, see `dot test shot` (log in the guest's /tmp/lsck0-install.log)"} }
        if (date now) > $deadline { error make {msg: $"the lsck0 iso's install still running after ($BOOTSTRAP_TIMEOUT)"} }
        sleep $POLL
    }
}

def bootstrap [name: string, iso: path, host: record, bundle: any, platform: string, user: string, profile: string]: nothing -> nothing {
    vm-destroy $name
    let lsck0 = iso-is-lsck0 $iso
    let cdrom = if $lsck0 { pool-iso $iso $LSCK0_VOLUME } else { pool-iso $iso $ISO_VOLUME }
    let answers = if $lsck0 {
        [--disk $"path=(pool-iso (answers-iso $name $bundle $platform $user $profile) (answers-volume $name) --fresh),device=cdrom,readonly=on"]
    } else { [] }
    let console = $CONSOLE_DIR | path join $"($name)-serial.log"
    (^sudo virt-install --connect $CONNECT --name $name --memory 12288 --vcpus 8 --cpu host-passthrough
        --serial $"file,path=($console)" --disk $"pool=($POOL),size=($DISK_GIB),format=qcow2,bus=virtio,discard=unmap" --cdrom $cdrom ...$answers
        --osinfo archlinux --network user,model=virtio --graphics spice --video virtio --noautoconsole
        --features smm.state=on
        --boot "uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=no")
    let follow = ^bash -c $"sudo -n tail --pid=($nu.pid) -n +1 -F '($console)' >&2 2>/dev/null & echo $!" | str trim
    if $lsck0 {
        lsck0-await $name
        ^kill $follow | complete | ignore
        virsh start $name | ignore
        return
    }
    wait-screen $name [root@archiso] $BOOT_TIMEOUT | ignore
    let checkout = if $bundle == null { "" } else {
        ^ln -sf $bundle ($host.dir | path join file snapshot.bundle)
        let lfs = snapshot-lfs $name
        let objects = if $lfs == null { "" } else {
            ^ln -sf $lfs ($host.dir | path join file snapshot-lfs.tar)
            $" && curl -s ($HOST)/file/snapshot-lfs.tar | tar -xC .git"
        }
        $" && curl -so /tmp/snapshot.bundle ($HOST)/file/snapshot.bundle && git fetch -q /tmp/snapshot.bundle ($SNAPSHOT_REF) && git checkout -q FETCH_HEAD($objects)"
    }
    let log = cache-dir $name | path join bootstrap.log
    host-upload-to $host $log
    let answers = $BOOTSTRAP_PASSTHROUGH | where {|n| $env | get --optional $n | is-not-empty } | each {|n|
        $"($n)='($env | get $n | str replace --all "'" "'\\''")' "
    } | str join
    # virt-install turns this first boot's reboot into a power off
    run-step $name $host bootstrap ([
        "set -o pipefail"
        "exec > >(tee /dev/ttyS0) 2>&1"
        "pacman -Sy --noconfirm --needed git"
        $"cd /tmp && git clone ($REPO_URL) && cd arch-dotfiles($checkout) \\"
        $"    && ($answers)BOOTSTRAP_DISK=($DISK) BOOTSTRAP_PASSWORD=($PASSWORD) BOOTSTRAP_USERNAME=($user) BOOTSTRAP_PROFILE=($profile) BOOTSTRAP_ASSUME_YES=1 ./bootstrap.sh ($platform) 2>&1 \\"
        "    | tee /tmp/bootstrap.log \\"
        $"    || { curl -sT /tmp/bootstrap.log ($HOST)/bootstrap.log; (beacon-cmd bootstrap-fail); }"
    ] | str join "\n" | $"($in)\n") us
    let deadline = (date now) + $BOOTSTRAP_TIMEOUT
    let failed = try {
        while (virsh domstate $name | str trim) != "shut off" {
            if (beacon $host bootstrap-fail $POLL) != null { error make {msg: $"bootstrap.sh failed, see ($log)"} }
            if (date now) > $deadline { error make {msg: $"bootstrap.sh still running after ($BOOTSTRAP_TIMEOUT)"} }
        }
        null
    } catch {|e| $e.msg }
    ^kill $follow | complete | ignore
    if $failed != null { error make {msg: $failed} }
    virsh start $name | ignore
}

# "nter passphrase", not "passphrase": the config stage prints secret names like borg-passphrase
def await-chain [name: string]: nothing -> nothing {
    let start = date now
    wait-screen $name ["nter passphrase" "root volume"] $CHAIN_TIMEOUT | ignore
    print $"dot test: chain done after ((date now) - $start)"
    type-text $name $"($PASSWORD)\n" de
}

# getty drops input typed before it cleared the screen, and the shell starts slowly: several beacon polls per login
export def login-tty [name: string, host: record, user: string]: nothing -> any {
    for attempt in 0..<$LOGIN_ATTEMPTS {
        sleep (if $attempt == 0 { $POLL } else { 3sec })
        virsh qemu-monitor-command $name --hmp $"sendkey ctrl-alt-f($LOGIN_TTY)" | ignore
        sleep 3sec
        type-text $name $"($user)\n" de
        sleep 3sec
        type-text $name $"($PASSWORD)\n" de
        sleep 5sec
        # the installed app firewall (portmaster) blocks the host beacon; verify does not need it
        clear-line $name
        type-text $name $"echo ($PASSWORD) | sudo -S systemctl stop portmaster.service 2>/dev/null\n" de
        for poll in 0..<4 {
            sleep 6sec
            clear-line $name
            let tag = $"login-($attempt)-($poll)"
            type-text $name $"(beacon-cmd $tag)\n" de
            if (beacon $host $tag 15sec) != null { return }
        }
    }
    error make {msg: $"login failed ($LOGIN_ATTEMPTS) times, see `dot test shot`"}
}

def invariants []: nothing -> table {
    open --raw ($REPO | path join scripts lib invariants.txt) | lines | where {|l| ($l | str trim | is-not-empty) and not ($l | str starts-with "#") }
    | parse --regex '^(?<key>\S+)\s+(?<want>\S+)\s+(?<where>\S+)\s+(?<probe>.*)$'
}

export def pull-logs [name: string, host: record]: nothing -> path {
    let out = cache-dir $name
    let tgz = $out | path join logs.tgz
    rm --force $tgz
    host-upload-to $host $tgz
    clear-line $name
    # string concatenation, not interpolation: in $'..' the probe's own "$(" would lose its paren to nu
    let probes = invariants | each {|i|
        let probe = $i.probe | str replace --all "@PASSWORD@" $PASSWORD | str replace --all "@DISK@" $DISK
        '    printf "%s=%s\n" ' + $i.key + ' "$(' + $probe + ')"'
    } | str join "\n"
    run-step $name $host logs ([
        "cd ~/projects/arch-dotfiles"
        "sudo -k"
        "{"
        $probes
        '    echo "backup_roundtrip=$(nu --no-config-file scripts/dot.nu internal backup --roundtrip > backup-roundtrip.log 2>&1 && echo ok || echo fail)"'
        "} > verify.log"
        "cp /var/lib/dotfiles-stage/log stage.log"
        $"echo ($PASSWORD) | sudo -S journalctl -u dotfiles-stage.service --no-pager -o short-iso > stage-journal.log"
        $"echo ($PASSWORD) | sudo -S journalctl -b -1 -p warning --no-pager -o short-iso > config-boot-warnings.log"
        "{ resolvectl status; cat /etc/resolv.conf; } > network.log 2>&1"
        "tar czf /tmp/vm-test-logs.tgz $(ls FAILURES.* 2>/dev/null) $(find . -name '*.log')"
        $"curl -sT /tmp/vm-test-logs.tgz ($HOST)/logs.tgz"
    ] | str join "\n" | $"($in)\n") de
    # the backup round trip runs first and may fetch a plasmoid into its empty home
    if not (host-uploaded $host $UPLOAD_TIMEOUT) { error make {msg: "no log upload arrived, see `dot test shot`"} }
    let logs = $out | path join logs
    rm --recursive --force $logs
    mkdir $logs
    ^tar -xzf $tgz -C $logs
    $logs
}

export def verify [logs: path]: nothing -> list<string> {
    let state = open --raw ($logs | path join verify.log) | lines | where ($it | str contains "=") | parse "{key}={value}" | reduce --fold {} {|r, acc| $acc | upsert $r.key $r.value }
    let expected = invariants | reduce --fold {backup_roundtrip: ok} {|i, acc| $acc | insert $i.key $i.want }
    let facts = $expected | items {|key, want| let got = $state | get --optional $key; if $got != $want { $"($key)=($got), expected ($want)" } } | compact
    let failures = glob ($logs | path join "FAILURES.*") | sort | where { open --raw $in | str trim | is-not-empty } | each {|f| $"($f | path basename):\n(open --raw $f | str trim --right)" }
    let stage_log = try { open --raw ($logs | path join stage.log) } catch { "" }
    let stages = [install config] | where {|s| not ($stage_log | str contains $"($s): ok") } | each { $"stage ($in) did not finish ok, see ($in).log" }
    $facts ++ $failures ++ $stages
}

export def vm-run [name: string, iso: path, platform: string, user: string, profile: string, master: bool]: nothing -> nothing {
    for t in [virt-install virsh tesseract magick socat xorriso blkid] {
        if (which $t | is-empty) { error make {msg: $"($t) missing"} }
    }
    if not ($iso | path exists) { error make {msg: $"no iso at ($iso)"} }
    sudo-keepalive
    let host = host-start $name (cache-dir $name | path join logs.tgz)
    bootstrap $name $iso $host (if $master { null } else { snapshot-bundle $name }) $platform $user $profile
    await-chain $name
    login-tty $name $host $user
    let logs = pull-logs $name $host
    host-stop $host
    print $"dot test: logs in ($logs)"
    let problems = verify $logs
    virsh qemu-monitor-command $name --hmp "sendkey ctrl-alt-f1" | ignore
    sleep 5sec
    print (screenshot $name)
    if ($problems | is-not-empty) { error make {msg: ($problems | str join "\n")} }
    print "dot test: chain succeeded, the screenshot shows the login manager"
}

def unlock [name: string, timeout: duration]: nothing -> bool {
    let deadline = (date now) + $timeout
    while (date now) < $deadline {
        let text = screen-text $name
        if ($text | str contains "nter passphrase") or ($text | str contains "root volume") {
            type-text $name $"($PASSWORD)\n" de
            return true
        }
        sleep $POLL
    }
    false
}

def drill-reboot [name: string, host: record, user: string, --again]: nothing -> nothing {
    if not (unlock $name $BOOT_TIMEOUT) { error make {msg: "no passphrase prompt after the drill's reboot, see `dot test shot`"} }
    if $again {
        sleep $DRILL_SETTLE
        unlock $name $BOOT_TIMEOUT | ignore
    }
    login-tty $name $host $user
}

# runs as root on the guest; SUDO_USER is the login
def drill-step [name: string, host: record, step: string, values: record = {}, files: record = {}]: nothing -> record {
    let scripts = [prelude $step] | each {|script|
        let text = open --raw ($VM_DIR | path join $"($script).nu") | str replace --all "@HOST@" $HOST
        $values | items {|k, v| {k: $k, v: ($v | into string)} } | reduce --fold $text {|kv, acc|
            if not ($kv.v =~ $DRILL_VALUE) { error make {msg: $"drill value ($kv.k)=($kv.v | to nuon) is no plain word, not handing it to the guest"} }
            $acc | str replace --all $"@($kv.k | str uppercase)@" $kv.v
        }
    }
    let left = $scripts | str join | parse --regex '(?<p>@[A-Z_]+@)' | get p | uniq
    if ($left | is-not-empty) { error make {msg: $"drill step ($step) left ($left | str join ' ') unfilled"} }
    let log = cache-dir $name | path join $"drill-($step).log"
    rm --force $log
    host-upload-to $host $log
    $scripts.0 | save --force ($host.dir | path join step prelude.nu)
    $scripts.1 | save --force ($host.dir | path join step $"($step).nu")
    $files | items {|suffix, text| $text | save --force ($host.dir | path join step $"($step).($suffix)") } | ignore
    clear-line $name
    let fetch = [prelude.nu $"($step).nu"] | each { $"curl -so /tmp/($in) ($HOST)/step/($in)" } | str join " && "
    run-step $name $host $step $"($fetch) && echo ($PASSWORD) | sudo -S -p '' nu --no-config-file /tmp/($step).nu > /tmp/($step).nu.log 2>&1\n" de
    if not (host-uploaded $host $DRILL_STEP_TIMEOUT) { error make {msg: $"drill step ($step) sent no report in ($DRILL_STEP_TIMEOUT), see `dot test shot`"} }
    open --raw $log | lines | parse --regex '^drill: (?<k>[a-z0-9_]+)=(?<v>.*)$' | reduce --fold {} {|r, acc| $acc | upsert $r.k $r.v }
}

def expect [step: string, got: record, want: record]: nothing -> list<string> {
    $want | items {|k, v| if ($got | get --optional $k) != $v { $"($step): ($k)=($got | get --optional $k), expected ($v)" } } | compact
}

# (phase, name, proto, daddr, dport, gid, marked): tuples portmaster-bypass.nft must or must not mark 1710
const BYPASS_MEMBER_GID = 4711
const BYPASS_PROBES = [
    [phase name proto daddr dport gid marked];
    [away lo_udp udp 127.0.0.1 5000 0 true] [away lo_tcp tcp 127.0.0.1 5001 0 true]
    [away lo_dns_udp udp 127.0.0.1 53 0 false] [away lo_dns_tcp tcp 127.0.0.1 53 0 false]
    [away lo_dot tcp 127.0.0.1 853 0 false] [away lo6_udp udp "::1" 5002 0 true] [away lo6_dns udp "::1" 53 0 false]
    [away labdns_away udp 192.168.178.29 53 0 false] [away lab_v4_10 udp 10.8.0.1 5003 0 true]
    [away lab_v4_172 tcp 172.16.1.1 5004 0 true] [away lab_v4_192 udp 192.168.50.1 5005 0 true]
    [away lab_internet udp 1.1.1.1 5006 0 false] [away lab_v6 udp "fd00::1" 5007 0 true]
    [away lab_v6_internet udp "2001:db8::1" 5008 0 false] [away wan_lab_range udp 172.20.1.1 5009 0 false]
    [away wan_member_gid udp 203.0.113.7 5010 4711 true] [away wan_member_gid6 udp "2001:db8:ff::7" 5011 4711 true]
    [away wan_other_gid udp 203.0.113.7 5012 4712 false] [away wan_root udp 203.0.113.7 5013 0 false]
    [home labdns_udp udp 192.168.178.29 53 0 true] [home labdns_tcp tcp 192.168.178.29 53 0 true]
    [home labdns_other_port udp 192.168.178.29 5353 0 false] [home home_other_dns udp 192.168.178.1 53 0 false]
    [home home_lan udp 192.168.178.5 5014 0 false]
]

# no proton secret in the vm: a throwaway config whose peer never answers, so anything reaching the host leaked
def drill-egress [name: string, host: record, user: string]: nothing -> list<string> {
    drain $host | ignore
    let bypass = open --raw ($VM_DIR | path join bypass.nu)
        | str replace "@MEMBER_GID@" ($BYPASS_MEMBER_GID | into string)
        | str replace "@PROBES@" ($BYPASS_PROBES | reject marked | to nuon)
    let got = drill-step $name $host egress {} {bypass: $bypass}
    let want = {bypass_deployed: yes, bypass_live_gids: yes}
        | merge ($BYPASS_PROBES | reduce --fold {} {|p, acc| $acc | insert $"bypass_($p.name)" (if $p.marked { "marked" } else { "unmarked" }) })
        | merge {
            vpn_conf: drill, vpn_module: ok, vpn_links: "lo,wg-protonvpn", vpn_routes: "default dev wg-protonvpn scope link"
            vpn_ipv6_off: "1", vpn_route_host: wg-protonvpn, vpn_run_user: $user, vpn_run_ns: yes, vpn_up_curl: no, vpn_up_dns: no
            vpn_down_route: none, vpn_down_curl: no, vpn_gone_links: lo, vpn_gone_leak: no, vpn_gone_run: refused
            vpn_gone_shim: refused, vpn_restart_links: "lo,wg-protonvpn", vpn_stopped_ns: absent, vpn_stopped_run: refused
        }
    let beacons = drain $host
    let control = if "drill-control" in $beacons { [] } else { ["egress: the control beacon never reached the host, so no leak beacon could have either"] }
    (expect egress $got $want) ++ $control ++ ($beacons | where ($it | str contains leak) | each { $"egress: ($in) reached the host from inside the namespace" })
}

# ROLLBACK.md's catch: kernel-resync must put the esp back in step and boot the old kernel
def drill-rollback [name: string, host: record, user: string]: nothing -> list<string> {
    let old = drill-step $name $host rollback-old
    let bad = expect rollback-old $old {downgraded: yes}
    if ($bad | is-not-empty) { return $bad }
    drill-reboot $name $host $user
    let vals = $old | select pkgbase kver_new kernel_new kernel_old
    let snap = drill-step $name $host rollback-snap $vals
    let bad = expect rollback-snap $snap {booted_old: yes, snapshot_made: yes, bumped: yes}
    if ($bad | is-not-empty) { return $bad }
    drill-reboot $name $host $user
    let vals = $vals | merge {kver_old: $snap.kver_old, snapshot: $snap.snapshot}
    let bumped = drill-step $name $host rollback-restore $vals
    let bad = expect rollback-restore $bumped {kver_bumped: $vals.kver_new, esp_kver: $vals.kver_new}
    if ($bad | is-not-empty) { return $bad }
    drill-reboot $name $host $user --again
    let after = drill-step $name $host rollback-verify $vals
    expect rollback-verify $after {
        kver_running: $vals.kver_old, pkg_version: $vals.kernel_old, modprobe: yes, esp_in_step: yes, marker_before: yes
        marker_after: no, resync_restored: yes, resync_rebooted: yes, resync_result: success
    }
}

export def vm-drill [name: string, drill: string, user: string]: nothing -> nothing {
    if $drill not-in [egress rollback] { error make {msg: $"no drill ($drill), one of egress rollback"} }
    sudo-keepalive
    match (virsh domstate $name | str trim) {
        "shut off" => {
            virsh start $name | ignore
            if not (unlock $name $BOOT_TIMEOUT) { error make {msg: $"($name) started but asked no passphrase, see `dot test shot`"} }
        }
        "running" => {}
        $state => { error make {msg: $"no installed vm ($name) \(($state | default missing)\), `dot test run` makes one"} }
    }
    let host = host-start $name (cache-dir $name | path join drill.log)
    login-tty $name $host $user
    let problems = if $drill == "egress" { drill-egress $name $host $user } else { drill-rollback $name $host $user }
    host-stop $host
    if ($problems | is-not-empty) { error make {msg: ($problems | str join "\n")} }
    print $"dot test: drill ($drill) passed, its logs are (cache-dir $name)/drill-*.log"
}

export def vm-logs [name: string, user: string]: nothing -> nothing {
    sudo-keepalive
    let host = host-start $name (cache-dir $name | path join logs.tgz)
    # a finished run leaves the console on ly's tty1, where pull-logs would type into the password field
    login-tty $name $host $user
    let logs = pull-logs $name $host
    host-stop $host
    print $logs
    let problems = verify $logs
    print (if ($problems | is-empty) { "dot test: verify found no problems" } else { $problems | str join "\n" })
}

export def vm-type [name: string, text: string, layout: string]: nothing -> nothing {
    type-text $name ($text | str replace --all '\n' "\n") $layout
}
