# before module.nu: a file imported after it parses its exec calls as module.nu's exec declaration
use offload.nu [OFFLOAD_ROLES OFFLOAD_ROLE_CLIENT OFFLOAD_ROLE_TARGET]
use module.nu *
use ../../../platforms/homelab.nu [HOMELAB]

# the target's address and knock are base/ssh's (wake_host, the desktop wake-pc wakes); the ports offload forward
# offers are the llm services' own sockets, read where they are declared. The target's sshd drop-in for the lab's
# builder goes in after base/ssh's own. Volatile: labworker's uid, there once sysusers made it, names its manager's
# drop-in.
export const meta = {
    deps: [base/ssh]
    inputs: [configs/llm/ollama/ollama.socket configs/llm/vllm/vllm.socket configs/llm/comfyui/comfyui.socket]
    volatile: true
}

export const options = {
    memory_cap_mib: {
        type: int?
        default: null
        doc: "MiB the offload jobs of one user may use together (offload.slice), a job's memoryMiB at most this; none: half the RAM"
        label: "Job memory cap (MiB)"
        min: 1024
    }
    cpus_cap: {
        type: int?
        default: null
        doc: "CPUs the offload jobs of one user may use together, a job's cpus at most this; none: half the cores"
        label: "Job CPU cap"
        min: 1
    }
}

const LLM = path self ../../llm
const FORWARD_SERVICES = [ollama vllm comfyui]
const LISTEN_LOOPBACK = '(?m)^ListenStream=127\.0\.0\.1:(?<port>\d+)\s*$'
const WORKER = "/usr/local/lib/offload/worker.nu"
const TMPFILES = "/etc/tmpfiles.d/offload.conf"
const USER_UNITS = "/etc/systemd/user"
const ENFORCE = "offload-enforce.path"
const LABWORKER = "labworker"
const LAB_HOME = "/var/lib/labworker"
const LAB_DEVICE = "lab-builder"
const LAB_SYSUSERS = "/etc/sysusers.d/offload-labworker.conf"
const LAB_TMPFILES = "/etc/tmpfiles.d/offload-labworker.conf"
const LAB_AUTHORIZED = "/etc/ssh/offload_authorized_keys"
const LAB_SSHD = "/etc/ssh/sshd_config.d/20-offload.conf"
# above SUB_UID_MAX, so useradd never hands this range to a login
const LAB_SUBIDS = "600200000-600265535"

def forwards-read []: nothing -> record {
    $FORWARD_SERVICES | each {|service|
        let socket = $LLM | path join $service $"($service).socket"
        let port = open --raw $socket | parse --regex $LISTEN_LOOPBACK | get --optional 0.port
        if $port == null { error make {msg: $"offload: ($socket) listens on no loopback port"} }
        [$service ($port | into int)]
    } | into record
}

export def packages [cfg: record]: nothing -> record {
    {pacman: (if $env.OFFLOAD? == $OFFLOAD_ROLE_TARGET { [podman] } else { [] })}
}

# The target's login half of the worker: the idle gate, the consent questions, the enforcement in this manager.
def target-session []: nothing -> list<any> {
    let values = {DOTFILES: $env.DOTFILES}
    [
        (file-render offload-gate.service (unit-dir | path join offload-gate.service) $values)
        (unit-enable offload-gate.service --now)
        (file-render offload-consent.service (unit-dir | path join offload-consent.service) $values)
        (unit-file offload-consent.path --enable --now)
        (if ($USER_UNITS | path join $ENFORCE | path exists) { unit-enable $ENFORCE --now })
    ]
}

# The platform fact offload names the role: the target runs the work, a client sends it there; no fact, no command.
export def link [cfg: record] {
    let role = $env.OFFLOAD? | default ""
    if $role == "" { return [] }
    if $role not-in $OFFLOAD_ROLES {
        error make {msg: $"offload: platform fact offload is '($role)', not one of ($OFFLOAD_ROLES | str join ', ')"}
    }
    let ssh = $cfg.deps."base/ssh"
    if $role == $OFFLOAD_ROLE_CLIENT and $ssh.wake_host == null {
        error make {msg: "offload: a client needs the target's address in base/ssh.wake_host"}
    }
    let homelab = platform-has homelab
    let config = {
        role: $role
        host: $ssh.wake_host
        port: $ssh.port
        knock: $ssh.knock
        router: (if $homelab { $ssh.wake_router })
        router_tunnel: (if $homelab { $ssh.wake_router_tunnel })
        forwards: (forwards-read)
    }
    let user = $env.USER? | default (^id -un | str trim)
    [
        (file-text (xdg config offload config.nuon) ($config | to nuon --indent 4) --generated)
        (link-commands offload.nu)
        # the target's user manager outlives the last login, so a job keeps running after a logout
        (if $role != $OFFLOAD_ROLE_CLIENT {
            let lingers = $"/var/lib/systemd/linger/($user)" | path exists
            exec offload-linger [loginctl enable-linger] --done=$lingers --undo [loginctl disable-linger]
        })
        (if $role == $OFFLOAD_ROLE_TARGET { target-session })
    ]
}

def memory-half []: nothing -> int {
    open /proc/meminfo | parse --regex '(?m)^MemTotal:\s+(?<kb>\d+) kB' | get 0.kb | into int | $in // 2048
}

def subids-done []: nothing -> bool {
    let start = $LAB_SUBIDS | split row "-" | first
    ["/etc/subuid" "/etc/subgid"] | all {|f|
        ($f | path exists) and (open --raw $f | lines | any { $in | str starts-with $"($LABWORKER):($start):" })
    }
}

# sshd without pam refuses a locked account ("!" in shadow, sysusers' default) even to a key: "*" has no password
# and is not locked
def unlocked [user: string]: nothing -> bool {
    try { open --raw /etc/shadow | lines | any { $in | str starts-with $"($user):*:" } } catch { false }
}

def uid-of [user: string]: nothing -> any {
    let got = do { ^id -u $user } | complete
    if $got.exit_code == 0 { $got.stdout | str trim }
}

# The lab's builder as a device of its own: the locked-down labworker user, its one key forced onto the worker's
# entry from the builder's address only, its sshd surface shut, its sub-ids for rootless podman, its manager lingering
# and hardened. Declared only once the lab published the key.
def labworker [builder: record, setup: list<string>]: nothing -> list<any> {
    let entry = $"/usr/bin/nu --no-config-file ($WORKER) serve ($LAB_DEVICE)"
    let key = $"restrict,from=\"($builder.ip)\",command=\"($entry)\" ($builder.key)\n"
    let uid = uid-of $LABWORKER
    let linger = $"/var/lib/systemd/linger/($LABWORKER)"
    let manager = [systemctl --user -M $"($LABWORKER)@"]
    [
        (file-text $LAB_SYSUSERS $"u ($LABWORKER) - \"offload lab worker\" ($LAB_HOME) /usr/bin/sh\n" --then $setup)
        (file-copy labworker.tmpfiles $LAB_TMPFILES --then $setup)
        (file-text $LAB_AUTHORIZED $key)
        (exec "offload labworker unlock" [usermod --password "*" $LABWORKER] --done=(unlocked $LABWORKER)
            --requires $LAB_HOME)
        (step sshd-dropin --key (open --raw labworker-sshd.conf | hash sha256)
            --undo [sh -c $"rm -f ($LAB_SSHD) && systemctl try-reload-or-restart sshd.service"])
        (exec $"offload labworker subids ($LAB_SUBIDS)"
            [usermod --add-subuids $LAB_SUBIDS --add-subgids $LAB_SUBIDS $LABWORKER] --done=(subids-done)
            --undo [usermod --del-subuids $LAB_SUBIDS --del-subgids $LAB_SUBIDS $LABWORKER] --requires $LAB_HOME)
        (exec "offload labworker linger" [loginctl enable-linger $LABWORKER] --done=($linger | path exists)
            --undo [loginctl disable-linger $LABWORKER] --requires $LAB_HOME)
        # linger starts the manager without waiting for it; starting its unit blocks until its bus is up
        (exec "offload labworker enforce" [sh -c $"systemctl start user@$\(id -u ($LABWORKER)\).service && exec \"$@\"" sh ...$manager enable --now $ENFORCE]
            --creates ($LAB_HOME | path join .config systemd user default.target.wants $ENFORCE)
            --undo [...$manager disable --now $ENFORCE] --requires $linger)
        # takes effect on the manager's next start (boot); a restart would kill a running job
        (if $uid != null {
            file-copy labworker-user.conf $"/etc/systemd/system/user@($uid).service.d/50-offload.conf" --then [systemctl daemon-reload]
        })
    ]
}

# The target's worker: the shared state, the caps, the worker's entry, every user's offload.slice and enforcement
# units; with the homelab's builder key also its labworker.
export def system [cfg: record] {
    if $env.OFFLOAD? != $OFFLOAD_ROLE_TARGET { return [] }
    let memory = $cfg.memory_cap_mib | default (memory-half)
    let cpus = $cfg.cpus_cap | default ([((^nproc | into int) // 2) 1] | math max)
    let builder = if (platform-has homelab) { $HOMELAB.builder? }
    let lab = $builder != null and $builder.key? != null
    let setup = [sh -c $"systemd-sysusers && systemd-tmpfiles --create ($TMPFILES)(if $lab { $' ($LAB_TMPFILES)' } else { '' })"]
    [
        (group-admins offload)
        (file-copy offload.tmpfiles $TMPFILES --then $setup)
        (file-text /etc/offload/limits.nuon ({memoryMiB: $memory, cpus: $cpus} | to nuon))
        (file-copy worker.nu $WORKER)
        (file-render offload.slice ($USER_UNITS | path join offload.slice) {MEMORY: $memory, CPU_QUOTA: ($cpus * 100)})
        (files-into $USER_UNITS offload-enforce.path offload-enforce.service)
        (if $lab { labworker $builder $setup })
    ]
}

# Installs the labworker sshd drop-in beside base/ssh's, kept only when sshd accepts the whole config.
export def sshd-dropin []: nothing -> nothing {
    let before = if ($LAB_SSHD | path exists) { open --raw $LAB_SSHD }
    open --raw labworker-sshd.conf | ^install -Dm644 /dev/stdin $LAB_SSHD
    if (^sshd -t | complete).exit_code != 0 {
        if $before == null { rm $LAB_SSHD } else { $before | save --force $LAB_SSHD }
        error make {msg: "offload: sshd rejects 20-offload.conf, kept the previous config"}
    }
    ^systemctl try-reload-or-restart sshd.service
}
