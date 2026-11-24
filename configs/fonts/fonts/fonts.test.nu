#!/usr/bin/env -S nu --no-config-file
# fonts.conf and the system's sarasa-generic.conf over the installed fonts: Han text under sans-serif takes Sarasa's
# Chinese forms, a lang tag its own region, a symbol DejaVu's narrow glyph, an emoji run the colour font. Builds its
# own font cache (about 15 MB, a few seconds) the way root builds the system's, without the user's drop-ins.
# Without Sarasa it skips.

const DIR = path self .

const CASES = [
    [pattern want];
    ["sans-serif" "Roboto"]
    ["sans-serif:charset=4e2d" "Sarasa Gothic SC"]
    ["Noto Sans:charset=4e2d" "Sarasa Gothic SC"]
    ["sans-serif:lang=zh-cn" "Sarasa Gothic SC"]
    ["sans-serif:lang=ja" "Sarasa Gothic J"]
    ["sans-serif:lang=ko" "Sarasa Gothic K"]
    ["monospace:charset=4e2d" "Sarasa Mono SC"]
    ["sans-serif:charset=2192" "DejaVu Sans"]
    ["sans-serif:lang=und-zsye" "Noto Color Emoji"]
]

def main [] {
    if (which fc-match fc-cache | length) < 2 or (^fc-list "Sarasa Gothic SC" family | str trim | is-empty) {
        print "fonts.test: skipped, no fontconfig or Sarasa Gothic"
        return
    }
    let dir = mktemp --directory --tmpdir fonts-test.XXXXXX
    # the repo's fonts.conf as the only user drop-in, where 50-user.conf loads it; the scan rule ahead of the system's
    # conf.d as /etc/fonts/conf.d/45-* would be; a cache of its own, as the system's lacks the scan rule
    mkdir ($dir | path join fontconfig conf.d)
    cp ($DIR | path join config fonts.conf) ($dir | path join fontconfig conf.d 50-dotfiles.conf)
    let conf = $dir | path join fonts.conf
    [
        '<?xml version="1.0"?>'
        '<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">'
        '<fontconfig>'
        '<dir>/usr/share/fonts</dir>'
        $"<include>($DIR | path join config sarasa-generic.conf)</include>"
        '<include ignore_missing="yes">/etc/fonts/conf.d</include>'
        $"<cachedir>($dir | path join cache)</cachedir>"
        '</fontconfig>'
    ] | to text | save $conf
    # root builds the system's cache without any user drop-in, and a font's genericfamily is fixed there
    mkdir ($dir | path join root)
    with-env {FONTCONFIG_FILE: $conf, XDG_CONFIG_HOME: ($dir | path join root)} { ^fc-cache }
    let failed = with-env {FONTCONFIG_FILE: $conf, XDG_CONFIG_HOME: $dir} {
        $CASES | each {|c|
            let got = ^fc-match $c.pattern family | split row "," | first
            if $got != $c.want { $"($c.pattern): ($got), want ($c.want)" }
        } | compact
    }
    rm --recursive $dir
    for line in $failed { print --stderr $"fonts.test: ($line)" }
    if ($failed | is-not-empty) { error make {msg: $"fonts.test: ($failed | length) fallbacks off"} }
}
