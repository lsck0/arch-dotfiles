use module.nu *

export const meta = {packages: {pacman: [obsidian]}}

const REST_VERSION = "5.4.0"
const REST_URL = $"https://github.com/coddingtonbear/obsidian-local-rest-api/releases/download/($REST_VERSION)"
const REST_SHA256 = {
    main.js: 1432a15543a927122524e4ea1951aac1cb9d0ed784a6d4836f1c771ea76b767f
    manifest.json: 50fca5cc8eadca296be46fa9ad11c14789b9e5fddf18fe058f6bc42e535372a6
    styles.css: 19956deaf4d14142381f81fdf92cae8241fd0aa08a1a3a5464b0d007bae1924d
}
const REST_ID = "obsidian-local-rest-api"
const REST_PORT = 27123
const VAULT = "documents/notes"
const VAULT_ID_LENGTH = 16
const API_KEY_BYTES = 32

def json-read [file: path]: nothing -> any {
    if ($file | path exists) { try { open $file } catch { null } } else { null }
}

# Enables the plugin in the vault's community-plugins.json, a json array json-merge cannot address.
export def plugin-enable [vault: path]: nothing -> nothing {
    let list = $vault | path join .obsidian community-plugins.json
    let enabled = json-read $list | default [] | where $it != $REST_ID
    mkdir ($list | path dirname)
    $enabled | append $REST_ID | to json | save --force $list
}

export def link [cfg: record] {
    let vault = $nu.home-dir | path join $VAULT
    let config = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join obsidian obsidian.json
    let plugin = $vault | path join .obsidian plugins $REST_ID
    let settings = $plugin | path join data.json
    let vaults = json-read $config | get --optional vaults | default {}
    let registered = $vaults | values | any { $in.path? == $vault }
    let vault_id = $vault | hash sha256 | str substring 0..($VAULT_ID_LENGTH - 1)
    let vault_entry = {path: $vault, ts: (date now | into int | $in // 1_000_000), open: ($vaults | is-empty)}
    let enabled = json-read ($vault | path join .obsidian community-plugins.json) | default [] | any { $in == $REST_ID }
    let key = json-read $settings | get --optional apiKey | default ""
    # plain http on loopback only: nothing here trusts its self-signed ca
    let server = [
        (json-set [bindingHost] "127.0.0.1") (json-set [enableInsecureServer] true) (json-set [insecurePort] $REST_PORT)
        (json-set [enableSecureServer] false)
    ]
    let mint = if ($key | is-empty) { [(json-set [apiKey] (random binary $API_KEY_BYTES | encode hex --lower))] } else { [] }
    let header = $"jq -c '{Authorization: \(\"Bearer \" + .apiKey\)}' '($settings)'"
    [
        (json-merge $config ([(json-set [cli] true)] ++ (if $registered { [] } else { [(json-set [vaults $vault_id] $vault_entry)] })))
        ($REST_SHA256 | items {|file, sha256| fetch-file $"($REST_URL)/($file)" $sha256 ($plugin | path join $file) } | flatten)
        (if $enabled { [] } else { step plugin-enable $vault })
        (json-merge $settings ($mint ++ $server) --then [chmod 600 $settings])
        (link-commands obsidian-launch.nu)
        (desktop-override obsidian.desktop { str replace --all --regex '(?m)^Exec=/usr/bin/obsidian' $"Exec=($nu.home-dir)/.local/bin/obsidian-launch" })
        (json-merge ($nu.home-dir | path join .claude.json) [
            (json-set [mcpServers obsidian-mcp] {type: http, url: $"http://127.0.0.1:($REST_PORT)/mcp/", headersHelper: $header})
        ])
    ]
}
