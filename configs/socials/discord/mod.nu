use module.nu *
use ../spotify/mod.nu [spicetify-colors]
use ../../core/wallust/palette.nu [RADIUS_PX hex-rgb255]
use ../../core/wallust/font.nu [font-load]

# its theme reads spotify's spicetify colours, so it runs after spotify's
export const meta = {deps: [socials/spotify], packages: {pacman: [discord discordo-git]}}

const BOOTSTRAP = "/usr/share/discord/updater_bootstrap"
const BOOTSTRAP_TIMEOUT = "900"
const UPDATES_URL = "https://updates.discord.com/"
const BOOTSTRAP_RUN = 'app=$(timeout "$1" "$2" --no-gui "$3" stable "$4") && ln -sfn "$3/$app/Discord" "$3/Discord"'
const THEME = "wal.theme.css"
const VOICE_PLUGIN = "plugins/QuickshellVoiceStatus.plugin.js"
# name: the plugin's @name, which betterdiscord keys plugins.json by; known before the fetch lands
const PLUGINS = [
    [name url sha256];
    ["BDFDB" "https://raw.githubusercontent.com/mwittrien/BetterDiscordAddons/368d78c137e8d6b65eb035330146ab3c8edf8d55/Library/0BDFDB.plugin.js" b19a521e026922750b882ecff61fe65413093b9b4d903798a1a9a08540ae3881] # committed 2026-11-10
    ["LastMessageDate" "https://raw.githubusercontent.com/mwittrien/BetterDiscordAddons/368d78c137e8d6b65eb035330146ab3c8edf8d55/Plugins/LastMessageDate/LastMessageDate.plugin.js" 0e9404a2cd54e719e0dd59bb5d0407f1939adea4b1f38f5d44726e9b5a2d2783] # committed 2026-11-10
    ["ZipPreview" "https://raw.githubusercontent.com/TheLazySquid/BetterDiscordPlugins/c667994891992d74ca170a27a8dcc0292620def0/plugins/ZipPreview/ZipPreview.plugin.js" bab7ae415b55a417a73f6f17a5ec0401e575140355a46a3576c4d91fabadc016] # committed 2026-11-09
    ["DoNotTrack" "https://raw.githubusercontent.com/zerebos/BetterDiscordAddons/6d839d0ab65371819b081218bc43b09d7d6e762d/Plugins/DoNotTrack/DoNotTrack.plugin.js" 6731d7a48ec8226779abf8251a22dcde30121613f21ffc5fcf3f45ed3fce7293] # committed 2024-12-15
    ["BetterDoubleClickToEdit" "https://raw.githubusercontent.com/Atamol/BetterDiscordPlugins/efad6c53bfacaca5ae92d5133245e0b172351ae0/BetterDoubleClickToEdit/BetterDoubleClickToEdit.plugin.js" b1504afc91de74d675f8c7b91e79a99cf713e0a996aac47b592d0017fcd76726] # committed 2026-08-17
    ["DoubleClickToReply" "https://raw.githubusercontent.com/Atamol/BetterDiscordPlugins/4474ed05346b0b413ee69feaf941a834b84209ea/DoubleClickToReply/DoubleClickToReply.plugin.js" b3fe23523625b4d915418b79ae859f5b2fef7f617abc464ca718bdefaf110f6a] # committed 2026-06-04
    ["LaTeX Generator" "https://raw.githubusercontent.com/Avasay-Sayava/BetterDiscordPlugins/f815fab3901db71fbe208bc3187d1ab146b0a24d/LaTeXGenerator/LaTeXGenerator.plugin.js" b2379f94f60bffe0a4bde09b47dca9da4d333802cc02351296dd461da5852d02] # committed 2026-04-18
    ["PriorityDM" "https://raw.githubusercontent.com/Snusene/BetterDiscordPlugins/a60205b18f394a2a2bf664194ab251532369dfc3/PriorityDM/PriorityDM.plugin.js" 8f527b1a8c3496fd3ff72a770e759597c37b13c066860194490fdb7c226beb7e] # committed 2026-05-21
    ["Incognito" "https://raw.githubusercontent.com/Snusene/BetterDiscordPlugins/8dd1d0732993fdb8821b9716cceb75452f4dafc4/Incognito/Incognito.plugin.js" d562fd9d2f3f0008c3b8f1a24cb178f15d1d8b0346df198897d8b878dc9aae5d] # committed 2026-10-23
    ["High-Res Profile Images" "https://raw.githubusercontent.com/Kawtious/HighResProfileImages/402830211b48dfd57ff4f4641722c29de2a9f279/HighResProfileImages.plugin.js" 7f4189573fd5bad08e47e3c087bba279b05022e37ab28d7e343918dfecd1ebda] # committed 2026-05-03
    ["OpenInApp" "https://raw.githubusercontent.com/fluzzeon/betterdiscord-OpenInApp/2b1f7c2c05af8abb16529dc9c248a224a15492c3/OpenInApp.plugin.js" 9910d9cfde13490328fb9387e2f02a222e090a679c82fec99590211e058cc7cc] # committed 2024-01-07
    ["SpotifyEnhance" "https://raw.githubusercontent.com/Skamt/BDAddons/bd3a9bb1630ae57cce608cbaa0cd60a73028a8ac/SpotifyEnhance/SpotifyEnhance.plugin.js" 968bc780312957ec16d503446f50454691bec8e172a24f9db8c6ff633c7037ce] # committed 2026-11-08
    ["Hide Chat Icons" "https://raw.githubusercontent.com/Farcrada/DiscordPlugins/c1250d3990ed3b9f1bf3518aa68050402929c52b/Hide-Chat-Icons/HideChatIcons.plugin.js" a3e3b4af105403b12b78a2168ad3a5adfecbe5f72d1dff06ed8c896cd259e085] # committed 2024-08-20
]
const SETTINGS = {
    # devtools stay on to debug the self-authored BetterDiscord plugin in plugins/; the self-XSS risk is accepted on this own machine
    DANGEROUS_ENABLE_DEVTOOLS_ONLY_ENABLE_IF_YOU_KNOW_WHAT_YOURE_DOING: true
    enableHardwareAcceleration: true
    offloadAdmControls: true
    asyncVideoInputDeviceInit: false
    enableLibOpenH264Electron: true
    openH264Enabled: true
}
const THEME_SLOTS = {
    accentcolor: button, backgroundprimary: main, backgroundsecondary: main
    backgroundsecondaryalt: main, backgroundtertiary: main, backgroundaccent: highlight
    backgroundfloating: main-elevated, textbrightest: text, textbrighter: text, textdark: subtext
}

def betterdiscord-dir []: nothing -> path {
    xdg config BetterDiscord
}

def addon-name [file: path]: nothing -> string {
    open --raw $file | lines | parse --regex '^\s*\*\s*@name\s+(?<name>.+)$' | get 0.name | str trim
}

export def link [cfg: record] {
    let config = xdg config discord
    let plugins = betterdiscord-dir | path join plugins
    let fetched = $PLUGINS | insert dest {|p| $plugins | path join ($p.url | path basename) }
    # betterdiscord adds a new addon disabled, keyed by its @name; the updater stays off, it would replace the pins
    let managed = $PLUGINS.name | append (addon-name $VOICE_PLUGIN)
    let data = betterdiscord-dir | path join data stable
    let plugin_states = $data | path join plugins.json
    let enabled = try { open $plugin_states } catch { {} }
    let disabled = $managed | where {|name| ($enabled | get --optional $name) != true }
    # betterdiscord reads plugins.json only at startup and rewrites it from memory, so a running client keeps them off
    if ($disabled | is-not-empty) and (process-running Discord) {
        log-note $"discord: restart Discord or enable in BetterDiscord settings: ($disabled | str join ', ')"
    }
    let bootstrapping = process-running updater_bootstr
    [
        (json-merge ($config | path join settings.json) $SETTINGS)
        (file-copy discordo.toml (xdg config discordo config.toml))
        # never beside a running bootstrap: they share one download dir
        (if not $bootstrapping and ($BOOTSTRAP | path exists) {
            let download = [sh -c $BOOTSTRAP_RUN discord-app $BOOTSTRAP_TIMEOUT $BOOTSTRAP $config $UPDATES_URL]
            exec discord-app $download --creates ($config | path join Discord) --network
        })
        # in place: betterdiscord disables an addon whose file is renamed over, and misses changes through a symlink
        (file-copy $VOICE_PLUGIN ($plugins | path join ($VOICE_PLUGIN | path basename)) --in-place)
        ($fetched | each {|p| fetch-file $p.url $p.sha256 $p.dest --in-place })
        (json-merge $plugin_states ($managed | each {|name| json-set [$name] true }))
        (json-merge ($plugins | path join Incognito.config.json) [
            (json-set [settings blockReadReceipts] false)
            (json-set [settings blockUsageProfiling] false)
            (json-set [settings anonymiseFiles] false)
            # on, it patches IdleStore.isIdle/isAFK to false: discord never goes idle or away when the pc is left
            (json-set [settings disableIdle] false)
        ])
        (json-merge ($data | path join themes.json) [(json-set [(addon-name $THEME)] true)])
        (json-merge ($data | path join settings.json) [(json-set [addons checkForUpdates] false)])
        # discord self-updates and relaunches past any wrapper, so the hook stays armed
        (user-hook betterdiscord-inject hook/betterdiscord-inject.nu --watch [
            "%h/.config/discord/Discord" "%h/.local/state/betterdiscord-modules"
        ])
        # discord's own cleanup deletes the openh264 build its host loads, so stream video fails to decode
        (user-hook discord-openh264 hook/openh264-restore.nu --watch [
            "%h/.config/discord/discord_asset_cache/openh264" "%h/.config/discord/Discord"
        ])
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let palette = spicetify-colors | default [] | reduce --fold {} {|c, acc| $acc | insert $c.key $c.hex }
    let font = font-load
    let colours = $THEME_SLOTS | items {|var, key| {var: $var, hex: ($palette | get --optional $key)} }
        | where hex != null | each {|c| {var: $c.var, value: ($c.hex | hex-rgb255 | str join ", ")} }
    let values = $colours ++ [
        {var: radius, value: $"($RADIUS_PX)px"} {var: font, value: $'"($font.family)"'} {var: font-scale, value: $font.scale}
    ]
    let text = $values | reduce --fold (open --raw $THEME) {|v, css|
        $css | str replace --regex --multiline ('^(\s*--' + $v.var + ':) .*$') $"${1} ($v.value);"
    }
    file-text (betterdiscord-dir | path join themes $THEME) $text --generated --in-place
}
