use module.nu *
use ../../core/wallust/font.nu [PX_PER_PT font-load]

export const meta = {packages: {pacman: [obsidian]}}

const REST_VERSION = "5.5.2"
const REST_URL = $"https://github.com/coddingtonbear/obsidian-local-rest-api/releases/download/($REST_VERSION)"
const REST_SHA256 = {
    # released 2026-10-17
    main.js: 90494b6444c5fede5d12f97346aab839265b5c7a09520fe87b4efc22360b6cd8
    manifest.json: 2ce46dfa1ee9b6150dd8dd0dbcc68636ee15d5433f9a3fa24e9b6cc8446ebe25
    styles.css: 19956deaf4d14142381f81fdf92cae8241fd0aa08a1a3a5464b0d007bae1924d
}
const REST_ID = "obsidian-local-rest-api"
const REST_PORT = 27123
const VAULT = "documents/notes"
# the vault's .obsidian is dot's and this machine's (the api key), so it stays out of ~/sync and the notes are linked in
const NOTES = "sync/notes"
const NOTES_LINK = "sync"
const VAULT_ID_LENGTH = 16
const API_KEY_BYTES = 32

def json-read [file: path]: nothing -> any {
    try { open $file } catch { null }
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
    let config = xdg config obsidian obsidian.json
    let plugin = $vault | path join .obsidian plugins $REST_ID
    let settings = $plugin | path join data.json
    let vaults = json-read $config | get --optional vaults | default {}
    # declared on every run with the value already there: a key declared only while missing is dropped, and so
    # deleted, by the next run, which sees it present
    let registered = $vaults | transpose id entry | where entry.path? == $vault | get --optional 0
    let vault_id = $registered.id? | default ($vault | hash sha256 | str substring 0..<$VAULT_ID_LENGTH)
    let vault_entry = $registered.entry? | default {path: $vault, ts: (date now | into int | $in // 1_000_000), open: ($vaults | is-empty)}
    let enabled = json-read ($vault | path join .obsidian community-plugins.json) | default [] | any { $in == $REST_ID }
    let key = json-read $settings | get --optional apiKey | default ""
    # plain http on loopback only: nothing here trusts its self-signed ca
    let server = [
        (json-set [bindingHost] "127.0.0.1") (json-set [enableInsecureServer] true) (json-set [insecurePort] $REST_PORT)
        (json-set [enableSecureServer] false)
    ]
    let api_key = if ($key | is-empty) { random binary $API_KEY_BYTES | encode hex --lower } else { $key }
    [
        # native: Hyprland's server-side frame instead of Obsidian's own window buttons in the tab bar
        (json-merge $config [(json-set [cli] true) (json-set [frame] native) (json-set [vaults $vault_id] $vault_entry)])
        ($REST_SHA256 | items {|file, sha256| fetch-file $"($REST_URL)/($file)" $sha256 ($plugin | path join $file) })
        (step plugin-enable $vault --done=$enabled)
        (file-link ($nu.home-dir | path join $NOTES) ($vault | path join $NOTES_LINK))
        # new notes and their attachments land beside the capture tools' notes, not in the unsynced vault root
        (json-merge ($vault | path join .obsidian app.json) [
            (json-set [newFileLocation] folder) (json-set [newFileFolderPath] $NOTES_LINK) (json-set [attachmentFolderPath] "./")
        ])
        (json-merge $settings ([(json-set [apiKey] $api_key)] ++ $server) --then [chmod 600 $settings])
        (link-commands obsidian-launch.nu)
        (desktop-override obsidian.desktop { str replace --all --regex '(?m)^Exec=/usr/bin/obsidian' $"Exec=($nu.home-dir)/.local/bin/obsidian-launch" })
        # gated: while Obsidian is closed a session shows a server with no tools, not a failed one
        (mcp-servers {obsidian-mcp: {
            type: http, url: $"http://127.0.0.1:($REST_PORT)/mcp/", headers: {Authorization: $"Bearer ($api_key)"}
            gate: {probe: $"127.0.0.1:($REST_PORT)", app: Obsidian}
        }})
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let font = font-load
    json-merge ($nu.home-dir | path join $VAULT .obsidian appearance.json) [
        (json-set [interfaceFontFamily] $font.family) (json-set [textFontFamily] $font.family)
        (json-set [monospaceFontFamily] $font.mono) (json-set [baseFontSize] ($font.size * $PX_PER_PT | math round))
    ]
}
