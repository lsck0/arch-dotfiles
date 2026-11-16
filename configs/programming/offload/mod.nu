# before module.nu: a file imported after it parses its exec calls as module.nu's exec declaration
use offload.nu [OFFLOAD_ROLES OFFLOAD_ROLE_CLIENT]
use module.nu *

# the target's address and knock are base/ssh's (wake_host, the desktop wake-pc wakes); the ports offload forward
# offers are the llm services' own sockets, read where they are declared
export const meta = {
    reads: [base/ssh]
    inputs: [configs/llm/ollama/ollama.socket configs/llm/vllm/vllm.socket configs/llm/comfyui/comfyui.socket]
}

const LLM = path self ../../llm
const FORWARD_SERVICES = [ollama vllm comfyui]
const LISTEN_LOOPBACK = '(?m)^ListenStream=127\.0\.0\.1:(?<port>\d+)\s*$'

def forwards-read []: nothing -> record {
    $FORWARD_SERVICES | each {|service|
        let socket = $LLM | path join $service $"($service).socket"
        let port = open --raw $socket | parse --regex $LISTEN_LOOPBACK | get --optional 0.port
        if $port == null { error make {msg: $"offload: ($socket) listens on no loopback port"} }
        [$service ($port | into int)]
    } | into record
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
    ]
}
