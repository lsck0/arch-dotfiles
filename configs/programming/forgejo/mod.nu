use module.nu *

# volatile: keys-register's stamp is cache state, so an unregistered key set plans the step again each run; cached, a
# run that could not reach forgejo (no DNS yet on a fresh install) would never retry
export const meta = {packages: {pacman: [tea]}, volatile: true}

const SECRET = "configs/secrets/keys/forgejo.env"

def env-read [file: path]: nothing -> record {
    open --raw $file | lines | parse --regex '^(?<k>[A-Z_]+)=(?<v>.*)$'
    | reduce --fold {} {|r, acc| $acc | insert $r.k ($r.v | str trim) }
}

# locked secrets keep the live file instead of dropping it
def kept [target: path]: nothing -> any {
    if ($target | path exists) { open --raw $target } else { null }
}

export def link [cfg: record] {
    if not (profile-has secrets) { return [] }
    let secret = $env.DOTFILES | path join $SECRET
    let store = xdg config git forgejo-credentials
    let inc = xdg config git forgejo.inc
    let tea = xdg config tea config.yml
    let ssh = $nu.home-dir | path join .ssh config.d forgejo
    let texts = if (secret-is-plaintext $secret) {
        let f = env-read $secret
        let host = $f.FORGEJO_URL | url parse | get host
        let ssh_url = $f.FORGEJO_SSH | url parse
        {
            store: $"https://($f.FORGEJO_USER):($f.FORGEJO_TOKEN)@($host)\n"
            inc: $"[credential \"($f.FORGEJO_URL)\"]\n\thelper =\n\thelper = store --file ($store)\n"
            tea: ({logins: [{name: lsck0, url: $f.FORGEJO_URL, token: $f.FORGEJO_TOKEN, default: true, ssh_host: $host, user: $f.FORGEJO_USER}]} | to yaml)
            ssh: ([$"Host ($host)" $"    HostName ($ssh_url.host)" $"    Port ($ssh_url.port)" "    User git"
                "    UserKnownHostsFile ~/.ssh/known_hosts.forgejo" "    StrictHostKeyChecking yes"] | str join "\n" | $"($in)\n")
        }
    } else {
        {store: (kept $store), inc: (kept $inc), tea: (kept $tea), ssh: (kept $ssh)}
    }
    if $texts.store == null { return [] }
    [
        ([[target text]; [$store $texts.store] [$tea $texts.tea] [$ssh $texts.ssh]] | where text != null
            | each {|f| file-text $f.target $f.text --mode 600 })
        (if $texts.inc == null { [] } else { file-text $inc $texts.inc })
        (file-copy known_hosts ($nu.home-dir | path join .ssh known_hosts.forgejo) --mode 600)
        (if (secret-is-plaintext $secret) and (keys-stamp | path exists) and (open --raw (keys-stamp)) == (keys-fingerprint) {
            []
        } else { step keys-register --network })
    ]
}

# The owner's ssh public keys readable here.
def keys-local []: nothing -> list<string> {
    $env.DOTFILES | path join configs secrets keys ssh_publickey.asc
    | append (glob ($env.DOTFILES | path join configs secrets yubikey ssh-*.pub))
    | append (glob ($nu.home-dir | path join .ssh *.pub))
    | where { secret-is-plaintext $in } | each { open --raw $in | str trim } | uniq
}

# Which keys went up to which account last: a new key or account registers again, the same set stays offline.
def keys-stamp []: nothing -> path { xdg cache dotfiles forgejo-keys }

def keys-fingerprint []: nothing -> string {
    let f = env-read ($env.DOTFILES | path join $SECRET)
    [$f.FORGEJO_URL $f.FORGEJO_USER ...(keys-local | sort)] | str join "\n" | hash sha256
}

# Adds the owner's ssh public keys to the Forgejo account; skipped away from the LAN and wireguard.
export def keys-register []: nothing -> nothing {
    let secret = $env.DOTFILES | path join $SECRET
    if not (secret-is-plaintext $secret) { return }
    let f = env-read $secret
    let api = $"($f.FORGEJO_URL)/api/v1/user/keys"
    let auth = [Authorization $"token ($f.FORGEJO_TOKEN)"]
    let have = try { http get --max-time 10sec --headers $auth $api | get key | each { split row ' ' | get 1 } } catch {|e|
        print $"note: forgejo: ssh keys not registered this run: ($e.msg)"
        return
    }
    let added = keys-local | each {|key|
        let parts = $key | split row ' '
        if ($parts | length) < 2 or $parts.1 in $have { return true }
        let title = $parts | get --optional 2 | default $parts.0
        try {
            http post --max-time 10sec --content-type application/json --headers $auth $api {title: $"($title) (sys host | get hostname)", key: $key} | ignore
            true
        } catch {|e| print $"note: forgejo: ssh key ($title) not added: ($e.msg)"; false }
    }
    if ($added | all { $in }) {
        mkdir (keys-stamp | path dirname)
        keys-fingerprint | save --force (keys-stamp)
    }
}
