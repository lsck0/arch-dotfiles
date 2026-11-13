use module.nu *
use ../../base/xdg/mod.nu [user-dir]

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
        (if (which kdenlive | is-not-empty) {
            ini-merge ($config | path join kdenliverc) {startup: {showWelcome: "false"}}
        })
        (if (which famistudio | is-not-empty) {
            let ini = $config | path join FamiStudio FamiStudio.ini
            [
                (ini-merge $ini {General: {Version: $FAMISTUDIO_SETTINGS_VERSION}} --missing-only)
                (ini-merge $ini {General: {ShowTutorial: "False"}})
                (desktop-override famistudio.desktop {
                    desktop-set {Version: "1.5", Categories: "AudioVideo;Audio;"}
                })
            ]
        })
        (if (which rawtherapee-cli | is-not-empty) {
            # -v exits 255
            let version = ^rawtherapee-cli -v | complete | get stdout | parse --regex 'version (?<v>[^,]+),' | get --optional 0.v
            if $version != null {
                ini-merge ($config | path join RawTherapee options) {General: {Version: $version}}
            }
        })
        (if (which lmms | is-not-empty) {
            let workdir = user-dir DOCUMENTS | path join lmms
            [
                (exec lmms-workdir [mkdir -p $workdir] --creates $workdir)
                (step lmms-paths $workdir --done=(lmms-rc | lmms-has-workdir))
            ]
        })
    ]
}

# lmms writes its whole rc on exit, so only the working dir is set, kept when lmms already has one of its own; without
# one lmms falls back to ~/lmms, which counts as none.
def lmms-rc []: nothing -> record {
    let rc = xdg config lmms lmmsrc.xml
    if ($rc | path exists) { open --raw $rc | from xml --allow-dtd } else { {tag: lmms, attributes: {}, content: []} }
}

def lmms-fallback []: nothing -> string { $"($nu.home-dir | path join lmms)/" }

def lmms-rc-workdir []: record -> string {
    get content | where {|e| $e.tag? == paths } | get --optional 0.attributes.workingdir | default ""
}

def lmms-has-workdir []: record -> bool {
    let dir = $in | lmms-rc-workdir
    $dir != "" and $dir != (lmms-fallback)
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
    # the fallback lmms made, or an earlier run did before user-dirs.dirs landed, goes once empty
    let fallback = lmms-fallback | str trim --right --char "/"
    if ($doc | lmms-rc-workdir) == (lmms-fallback) and ($fallback | path exists) and (ls --all $fallback | is-empty) {
        rm $fallback
    }
    mkdir ($rc | path dirname)
    $"<?xml version=\"1.0\"?>\n<!DOCTYPE lmms-config-file>\n($doc | update content $content | to xml)\n" | save --force $rc
}
