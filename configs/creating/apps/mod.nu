use module.nu *

export const meta = {
    packages: {
        pacman: [
            aseprite cava converseen drawy famistudio-bin feh giflib gifsicle gpu-screen-recorder handbrake kdenlive
            lmms lorien-bin rawtherapee sfxr-qt-bin sox tiled xournalpp
        ]
    }
}

# without it famistudio takes the file for a fresh install and resets every key
const FAMISTUDIO_SETTINGS_VERSION = 11

export def link [cfg: record] {
    let config = $nu.home-dir | path join .config
    [
        (if (which kdenlive | is-empty) { [] } else {
            ini-merge ($config | path join kdenliverc) {startup: {showWelcome: "false"}}
        })
        (if (which famistudio | is-empty) { [] } else {
            let ini = $config | path join FamiStudio FamiStudio.ini
            [
                (ini-merge $ini {General: {Version: $FAMISTUDIO_SETTINGS_VERSION}} --missing-only)
                (ini-merge $ini {General: {ShowTutorial: "False"}})
            ] ++ (
                desktop-override famistudio.desktop {
                    str replace --regex '(?m)^Version=.*$' "Version=1.5" | str replace --regex '(?m)^Categories=.*$' "Categories=AudioVideo;Audio;"
                }
            )
        })
        (if (which rawtherapee-cli | is-empty) { [] } else {
            # -v exits 255
            let version = ^rawtherapee-cli -v | complete | get stdout | parse --regex 'version (?<v>[^,]+),' | get 0.v
            ini-merge ($config | path join RawTherapee options) {General: {Version: $version}}
        })
        (if (which lmms | is-empty) { [] } else {
            let workdir = ^xdg-user-dir DOCUMENTS | str trim | path join lmms
            exec lmms-workdir [mkdir -p $workdir] --creates $workdir
        })
    ]
}
