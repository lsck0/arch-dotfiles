use module.nu *
use ../spotify/mod.nu [spicetify-colors]

export const meta = {packages: {pacman: [discord discordo-git]}}

const BOOTSTRAP = "/usr/share/discord/updater_bootstrap"
const BOOTSTRAP_TIMEOUT = "900"
const UPDATES_URL = "https://updates.discord.com/"
# /usr/bin/discord's first run: the bootstrap prints the app dir it filled, the launcher links <config>/Discord into it
const BOOTSTRAP_RUN = 'app=$(timeout "$1" "$2" --no-zenity "$3" stable "$4") && ln -sfn "$3/$app/Discord" "$3/Discord"'
const THEME = "wal.theme.css"
const VOICE_PLUGIN = "plugins/QuickshellVoiceStatus.plugin.js"
# raw files at commit shas, pinned by content too
const PLUGINS = [
    [url sha256];
    ["https://raw.githubusercontent.com/mwittrien/BetterDiscordAddons/21c049bb77fbe3ffc5cda8961830c098fc6bccad/Library/0BDFDB.plugin.js" 4f4e0180f1977167f70bc7562c4e45cdb096d074805a74742f74e53602f7534a]
    ["https://raw.githubusercontent.com/mwittrien/BetterDiscordAddons/21c049bb77fbe3ffc5cda8961830c098fc6bccad/Plugins/LastMessageDate/LastMessageDate.plugin.js" f3776c25941f1b8d1c7ae8af7f1be88d3afa054ef6858d9dde6980d8e5f4fc5a]
    ["https://raw.githubusercontent.com/TheLazySquid/BetterDiscordPlugins/3ce443c86a14185b2b2d088e9be49b8245d17c6c/plugins/ZipPreview/ZipPreview.plugin.js" ebdf6b1c3fe2ff0c4f3c34b4ba436e21f663ab77f49f3ee0fa2348916ed957e8]
    ["https://raw.githubusercontent.com/zerebos/BetterDiscordAddons/6d839d0ab65371819b081218bc43b09d7d6e762d/Plugins/DoNotTrack/DoNotTrack.plugin.js" 6731d7a48ec8226779abf8251a22dcde30121613f21ffc5fcf3f45ed3fce7293]
    ["https://raw.githubusercontent.com/Atamol/BetterDiscordPlugins/a0800b14b2462c4af1361dd9c79490b88ff649b6/BetterDoubleClickToEdit/BetterDoubleClickToEdit.plugin.js" ec5dc7e59f3687e4daa3edd1a8f1ac3c724de42ba7a31474c1c44db3015baad3]
    ["https://raw.githubusercontent.com/Atamol/BetterDiscordPlugins/4474ed05346b0b413ee69feaf941a834b84209ea/DoubleClickToReply/DoubleClickToReply.plugin.js" b3fe23523625b4d915418b79ae859f5b2fef7f617abc464ca718bdefaf110f6a]
    ["https://raw.githubusercontent.com/Avasay-Sayava/BetterDiscordPlugins/f815fab3901db71fbe208bc3187d1ab146b0a24d/LaTeXGenerator/LaTeXGenerator.plugin.js" b2379f94f60bffe0a4bde09b47dca9da4d333802cc02351296dd461da5852d02]
    ["https://raw.githubusercontent.com/Snusene/BetterDiscordPlugins/a60205b18f394a2a2bf664194ab251532369dfc3/PriorityDM/PriorityDM.plugin.js" 8f527b1a8c3496fd3ff72a770e759597c37b13c066860194490fdb7c226beb7e]
    ["https://raw.githubusercontent.com/Snusene/BetterDiscordPlugins/c53818992addc44fa3c3dcea4567a2ff3c9bdb2a/Incognito/Incognito.plugin.js" aaf30cc775aed81f3db0cc69afc05d92d8472856ad637f263798c8fc8bf4d1b4]
    ["https://raw.githubusercontent.com/Kawtious/HighResProfileImages/402830211b48dfd57ff4f4641722c29de2a9f279/HighResProfileImages.plugin.js" 7f4189573fd5bad08e47e3c087bba279b05022e37ab28d7e343918dfecd1ebda]
    ["https://raw.githubusercontent.com/fluzzeon/betterdiscord-OpenInApp/2b1f7c2c05af8abb16529dc9c248a224a15492c3/OpenInApp.plugin.js" 9910d9cfde13490328fb9387e2f02a222e090a679c82fec99590211e058cc7cc]
    ["https://raw.githubusercontent.com/Skamt/BDAddons/20be7c0e79ddd8b7e6d290c14ebe49aef5f7f650/SpotifyEnhance/SpotifyEnhance.plugin.js" b587949472153b720ea5ca14e39d790a83f430968679bad956c67060223712a1]
    ["https://raw.githubusercontent.com/Farcrada/DiscordPlugins/c1250d3990ed3b9f1bf3518aa68050402929c52b/Hide-Chat-Icons/HideChatIcons.plugin.js" a3e3b4af105403b12b78a2168ad3a5adfecbe5f72d1dff06ed8c896cd259e085]
]
# the app's own preferences; window state and the rest of settings.json stay discord's
const SETTINGS = {
    DANGEROUS_ENABLE_DEVTOOLS_ONLY_ENABLE_IF_YOU_KNOW_WHAT_YOURE_DOING: true
    enableHardwareAcceleration: true
    offloadAdmControls: true
    asyncVideoInputDeviceInit: false
    enableLibOpenH264Electron: true
    openH264Enabled: true
}
# the theme's colour variables and the spicetify palette key each takes, so discord matches spotify
const THEME_SLOTS = {
    accentcolor: button, accentcolor2: button, backgroundprimary: main, backgroundsecondary: main
    backgroundsecondaryalt: main, backgroundtertiary: main, backgroundaccent: highlight
    backgroundfloating: main-elevated, textbrightest: text, textbrighter: text, textdark: subtext
}

def bd []: nothing -> path {
    $nu.home-dir | path join .config BetterDiscord
}

def addon-name [file: path]: nothing -> string {
    open --raw $file | lines | parse --regex '^\s*\*\s*@name\s+(?<name>.+)$' | get 0.name | str trim
}

export def link [cfg: record] {
    let config = $nu.home-dir | path join .config discord
    let plugins = bd | path join plugins
    let fetched = $PLUGINS | insert dest {|p| $plugins | path join ($p.url | path basename) }
    # betterdiscord adds a new addon disabled, keyed by its @name; the updater stays off, it would replace the pins
    let managed = $fetched.dest | where ($it | path exists) | append $VOICE_PLUGIN
    let data = bd | path join data stable
    let bootstrapping = ps | where name == updater_bootstr | is-not-empty
    [
        (json-merge ($config | path join settings.json) ($SETTINGS | items {|k, v| json-set [$k] $v }))
        # the first run downloads the app (~150 MB) before any window; never beside a running bootstrap, one download dir
        (if $bootstrapping or not ($BOOTSTRAP | path exists) { [] } else {
            let download = [sh -c $BOOTSTRAP_RUN discord-app $BOOTSTRAP_TIMEOUT $BOOTSTRAP $config $UPDATES_URL]
            exec discord-app $download --creates ($config | path join Discord)
        })
        # copies: betterdiscord misses changes through a symlink
        (file-copy $VOICE_PLUGIN ($plugins | path join ($VOICE_PLUGIN | path basename)))
        ($fetched | each {|p| fetch-file $p.url $p.sha256 $p.dest } | flatten)
        (json-merge ($data | path join plugins.json) ($managed | each {|f| json-set [(addon-name $f)] true }))
        # incognito swallows the read-state ack, so anything read here stays unread on the phone
        (json-merge ($plugins | path join Incognito.config.json) [
            (json-set [settings blockReadReceipts] false)
        ])
        (json-merge ($data | path join themes.json) [(json-set [(addon-name $THEME)] true)])
        (json-merge ($data | path join settings.json) [(json-set [addons checkForUpdates] false)])
        # discord self-updates and relaunches past any wrapper, so the hook stays armed
        (user-hook betterdiscord-inject hook/betterdiscord-inject.nu --watch [
            "%h/.config/discord/Discord" "%h/.local/state/betterdiscord-modules"
        ])
    ]
}

def rgb [hex: string]: nothing -> string {
    $hex | str trim --left --char "#" | split chars | chunks 2 | each { str join | into int --radix 16 } | str join ", "
}

# generated, so betterdiscord's live copy is rewritten on every switch and never drifts
export def theme [cfg: record, wallpaper: string] {
    let palette = spicetify-colors | default [] | reduce --fold {} {|c, acc| $acc | insert $c.key $c.hex }
    let font = try { ^($env.DOTFILES | path join scripts toggles toggle-font.nu) get | str trim } catch { "" }
    let colours = $THEME_SLOTS | items {|var, key| {var: $var, hex: ($palette | get --optional $key)} }
        | where hex != null | each {|c| {var: $c.var, value: (rgb $c.hex)} }
    let values = $colours ++ (if ($font | is-empty) { [] } else { [{var: font, value: $'"($font)"'}] })
    let text = $values | reduce --fold (open --raw $THEME) {|v, css|
        $css | str replace --regex --multiline ('^(\s*--' + $v.var + ':) .*$') $"${1} ($v.value);"
    }
    file-text (bd | path join themes $THEME) $text --generated --in-place
}
