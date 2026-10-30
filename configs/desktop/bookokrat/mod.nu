use module.nu *

# config.yaml's synctex_editor runs sioyek's synctex-edit
export const meta = {deps: [latex/sioyek], packages: {pacman: [bookokrat-bin]}}

const SEED = path self config.yaml

def config-file []: nothing -> path { xdg config bookokrat config.yaml }

def scheme-file []: nothing -> path { xdg cache wal colors-bookokrat.yaml }

export def link [cfg: record] {
    let dest = config-file
    # seeded once: bookokrat rewrites config.yaml at runtime, so a repo edit only reaches a fresh install
    exec bookokrat-seed [install -Dm644 config.yaml $dest] --creates $dest
}

# Merged, not rendered: only the selected theme, its scheme and the synctex editor are forced.
export def theme [cfg: record, wallpaper: string] {
    let file = config-file
    let scheme_file = scheme-file
    if not ($file | path exists) or not ($scheme_file | path exists) { return [] }
    let editor = open $SEED | get synctex_editor
    let scheme = open $scheme_file
    let config = open $file
    let current = $config.custom_themes? | default [] | where scheme == $scheme.scheme
    if $config.theme? == $scheme.scheme and $current == [$scheme] and $config.synctex_editor? == $editor { return [] }
    step bookokrat-config-merge $file $scheme_file $editor
}

export def bookokrat-config-merge [file: path, scheme_file: path, synctex_editor: string]: nothing -> nothing {
    let scheme = open $scheme_file
    let config = open $file
    let others = $config.custom_themes? | default [] | where scheme != $scheme.scheme
    $config
    | upsert theme $scheme.scheme
    | upsert custom_themes ($others | append $scheme)
    | upsert synctex_editor $synctex_editor
    | to yaml
    | save --force $file
}
