use module.nu *

export const meta = {
    packages: {
        pacman: [
            aseprite cava converseen drawy famistudio-bin feh giflib gifsicle gpu-screen-recorder handbrake kdenlive
            lmms lorien-bin rawtherapee sfxr-qt-bin sox tiled xdg-user-dirs xournalpp
        ]
    }
}

# without it famistudio takes the file for a fresh install and resets every key
const FAMISTUDIO_SETTINGS_VERSION = 11

export def link [cfg: record] {
    let config = xdg config
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
                    desktop-set {Version: "1.5", Categories: "AudioVideo;Audio;"}
                }
            )
        })
        (if (which rawtherapee-cli | is-empty) { [] } else {
            # -v exits 255
            let version = ^rawtherapee-cli -v | complete | get stdout | parse --regex 'version (?<v>[^,]+),' | get --optional 0.v
            if $version == null { [] } else {
                ini-merge ($config | path join RawTherapee options) {General: {Version: $version}}
            }
        })
        (if (which lmms | is-empty) { [] } else {
            let workdir = ^xdg-user-dir DOCUMENTS | str trim | path join lmms
            [
                (exec lmms-workdir [mkdir -p $workdir] --creates $workdir)
                (step lmms-paths $workdir --done=(lmms-rc | lmms-has-workdir))
            ]
        })
    ]
}

# lmms writes its whole rc on exit, so only the working dir is set, kept when lmms already has one; without it lmms
# falls back to ~/lmms.
def lmms-rc []: nothing -> record {
    let rc = xdg config lmms lmmsrc.xml
    if ($rc | path exists) { open --raw $rc | from xml --allow-dtd } else { {tag: lmms, attributes: {}, content: []} }
}

def lmms-has-workdir []: record -> bool {
    get content | any {|e| $e.tag? == paths and ($e.attributes?.workingdir? | default "") != "" }
}

export def lmms-paths [workdir: string]: nothing -> nothing {
    let rc = xdg config lmms lmmsrc.xml
    let doc = lmms-rc
    let dir = $"($workdir)/"
    let content = if ($doc.content | any {|e| $e.tag? == paths }) {
        $doc.content | each {|e| if $e.tag? == paths { $e | upsert attributes.workingdir $dir } else { $e } }
    } else {
        $doc.content | append {tag: paths, attributes: {workingdir: $dir}, content: []}
    }
    mkdir ($rc | path dirname)
    $"<?xml version=\"1.0\"?>\n<!DOCTYPE lmms-config-file>\n($doc | update content $content | to xml)\n" | save --force $rc
}
