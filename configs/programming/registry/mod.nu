use module.nu *

export const meta = {packages: {pacman: [podman]}}

const SECRET = "configs/secrets/keys/registry.env"
# part of the login's key: a bump logs in once more, so the record takes this version's undo
const LOGIN_VERSION = 2

# The homelab registry's login. podman's ~/.config/containers/auth.json (read after the runtime dir's) is dot's own
# file. docker's ~/.docker/config.json is docker's: it keeps other logins, contexts and buildx aliases there, so dot
# only runs `docker login` into it, which merges the one entry; the password goes through stdin, never argv. Repos
# with an .identity set DOCKER_CONFIG to their own dir and log in there themselves.
export def link [cfg: record] {
    if not (profile-has secrets) { return [] }
    let secret = $env.DOTFILES | path join $SECRET
    let target = xdg config containers auth.json
    let unlocked = secret-is-plaintext $secret
    let json = if $unlocked {
        let r = env-file-load $secret
        let auth = $"($r.REGISTRY_USER):($r.REGISTRY_PASSWORD)" | encode base64
        {auths: {$r.REGISTRY_URL: {auth: $auth}}} | to json
    } else { file-trim $target null }
    [
        (if $json != null { file-text $target $"($json)\n" --mode 600 })
        (if (which docker | is-not-empty) {
            if $unlocked {
                # keyed on the secret's hash: a changed password logs in again. The undo names the url itself: it may run
                # while the secrets are locked, and sourcing the ciphertext then would log out of docker hub
                let key = open --raw $secret | hash sha256 | $"($in)-($LOGIN_VERSION)"
                let url = env-file-load $secret | get REGISTRY_URL
                let login = 'set -a; . "$0"; printf %s "$REGISTRY_PASSWORD" | docker login --username "$REGISTRY_USER" --password-stdin "$REGISTRY_URL" >/dev/null'
                (exec "docker login" [sh -c $login $secret] --key $key --network --undo [docker logout $url])
            } else {
                # still declared while locked, so it is no orphan whose undo logs out
                exec "docker login" [docker login] --done
            }
        })
    ] | compact
}
