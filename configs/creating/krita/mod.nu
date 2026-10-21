use module.nu *

export const meta = {packages: {pacman: [krita kseexpr]}}

const HERE = path self | path dirname
const BUILD_TIMEOUT = "900"

def data-dir []: nothing -> path {
    $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join krita
}

export def link [cfg: record] {
    if (which kritarunner | is-empty) or (data-dir | path join resourcecache.sqlite | path exists) { return [] }
    step resource-db
}

# Prebuilds the resource db krita's first start builds for minutes under its splash; built aside, then moved in.
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
    ^cp -an $"($built)/." (data-dir)
    rm --recursive $tmp
}
