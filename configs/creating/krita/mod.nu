use module.nu *

export const meta = {packages: {pacman: [krita]}}

const HERE = path self | path dirname
const BUILD_TIMEOUT = "900"

def data-dir []: nothing -> path {
    $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join krita
}

# krita's first start builds its font previews under the splash for minutes, long enough to look hung
export def link [cfg: record] {
    if (which kritarunner | is-empty) or (data-dir | path join resourcecache.sqlite | path exists) { return [] }
    step resource-db
}

# built in a scratch home and moved in, so an interrupted build never leaves a half db; offscreen for a tty install
export def resource-db []: nothing -> nothing {
    let tmp = mktemp --directory
    let scratch = {XDG_DATA_HOME: ($tmp | path join data), XDG_CONFIG_HOME: ($tmp | path join config)}
    with-env ($scratch | merge {QT_QPA_PLATFORM: offscreen, PYTHONPATH: $HERE}) {
        ^timeout $BUILD_TIMEOUT kritarunner -s warm | ignore
    }
    let built = $tmp | path join data kritarunner
    if not ($built | path join resourcecache.sqlite | path exists) {
        error make {msg: "krita: kritarunner built no resource db"}
    }
    mkdir (data-dir)
    # no-clobber: a data dir that only lost its db keeps everything else a person put there
    ^cp -an $"($built)/." (data-dir)
    rm --recursive $tmp
}
