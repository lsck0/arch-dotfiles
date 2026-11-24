# The syntax, diagnostic, diff and surface roles every editor theme shares (nvim, zed, emacs, delta), derived from the
# wal palette on the background the editor draws: one hue per role, each readable there.

use palette.nu [
    SHADE_CHROME SHADE_CURRENT SHADE_HOVER TEXT_RATIO contrast dim-toward is-light mix passes readable-on rgb-to-hex
    hue-apart semantic shade
]

export const COMMENT_RATIO = 4.0
const COMMENT_RATIO_MAX = 5.5
const PUNCTUATION_RATIO_MAX = 6.0
const GUTTER_RATIO = 3.0
const LINE_NUMBER_RATIO_MAX = 3.6
const BORDER_RATIO = 2.0
const BORDER_RATIO_MAX = 2.6
const TINT_STEP = 0.03
const TINT_SELECTION = 0.32
const TINT_SEARCH = 0.38
const TINT_DIFF_LINE = 0.18
const TINT_DIFF_CHANGE = 0.12
const TINT_DIFF_TEXT = 0.32
const TINT_PARAMETER = 0.35
const TINT_PROPERTY = 0.3
const MIX_CONSTANT = 0.45
const SYNTAX_APART_MIN_DEG = 18.0
const BLACK = [0.0 0.0 0.0]
const WHITE = [1.0 1.0 1.0]

# color mixed into bg at most by t, less until fg stays readable on it.
def tint-under [fg: list<float>, bg: list<float>, color: list<float>, t: float]: nothing -> list<float> {
    mut out = mix $bg $color $t
    mut step = $t
    while $step > $TINT_STEP and not (passes $fg $out $TEXT_RATIO) {
        $step = $step - $TINT_STEP
        $out = mix $bg $color $step
    }
    $out
}

# bg itself as text on a filled color when it reads there, else black or white.
def text-on [fill: list<float>, bg: list<float>]: nothing -> list<float> {
    if (passes $bg $fill $TEXT_RATIO) { return $bg }
    if (contrast $BLACK $fill) > (contrast $WHITE $fill) { $BLACK } else { $WHITE }
}

# Each role's first candidate whose hue is SYNTAX_APART_MIN_DEG from every role picked before it, else its first; in
# role order, so a palette with two near hues (rose-pine's pine and foam) still gives each role its own.
def syntax-pick [candidates: record, bg: list<float>]: nothing -> record {
    $candidates | items {|role, slots| {role: $role, slots: ($slots | each { readable-on $bg })} }
        | reduce --fold {} {|row, picked|
            let apart = $row.slots | where {|c| $picked | values | all { (hue-apart $c $in) >= $SYNTAX_APART_MIN_DEG } }
            $picked | insert $row.role ($apart | get --optional 0 | default $row.slots.0)
        }
}

# The palette-rgb record as editor roles in #rrggbb, for an editor whose background is bg.
export def editor-roles [bg: list<float>]: record -> record {
    let p = $in
    let text = {|c| $c | readable-on $bg }
    let gutter = {|c| $c | readable-on $bg --ratio $GUTTER_RATIO }
    let fg = $p.fg | readable-on $bg --ratio 7.0
    let search = $p.c3 | readable-on $bg --ratio $GUTTER_RATIO
    let syntax = syntax-pick {
        function: [$p.c4 $p.c12 $p.c6]
        keyword: [$p.c5 $p.c13 $p.c6 $p.c1]
        string: [$p.c2 $p.c10 $p.c6 $p.c3]
        type: [$p.c3 $p.c11 $p.c6 $p.c5]
        constant: [(mix $p.c1 $p.c3 $MIX_CONSTANT) $p.c1 $p.c9 $p.c6]
    } $bg
    let roles = {
        bg: $bg
        fg: $fg
        surface: ($bg | shade $SHADE_CHROME)
        surface_hover: ($bg | shade $SHADE_HOVER)
        current: ($bg | shade $SHADE_CURRENT)
        comment: ($p.c8 | dim-toward $bg --ratio $COMMENT_RATIO_MAX | readable-on $bg --ratio $COMMENT_RATIO)
        punctuation: ($fg | dim-toward $bg --ratio $PUNCTUATION_RATIO_MAX | readable-on $bg)
        line_number: ($p.c8 | dim-toward $bg --ratio $LINE_NUMBER_RATIO_MAX | readable-on $bg --ratio $GUTTER_RATIO)
        border: ($p.c8 | dim-toward $bg --ratio $BORDER_RATIO_MAX | readable-on $bg --ratio $BORDER_RATIO)
        builtin: (do $text $p.c6)
        tag: (do $text $p.c1)
        property: (do $text (mix $fg $p.c4 $TINT_PROPERTY))
        parameter: (do $text (mix $fg $p.c1 $TINT_PARAMETER))
        error: ($p.c1 | semantic error $bg)
        warn: ($p.c3 | semantic warn $bg)
        ok: ($p.c2 | semantic ok $bg)
        info: (do $text $p.c4)
        hint: (do $text $p.c6)
        added: (do $gutter $p.c2)
        changed: (do $gutter $p.c3)
        removed: (do $gutter $p.c1)
        selection: (tint-under $fg $bg $p.c4 $TINT_SELECTION)
        search: (tint-under $fg $bg $p.c3 $TINT_SEARCH)
        search_current: $search
        search_current_text: (text-on $search $bg)
        diff_add: (tint-under $fg $bg $p.c2 $TINT_DIFF_LINE)
        diff_delete: (tint-under $fg $bg $p.c1 $TINT_DIFF_LINE)
        diff_change: (tint-under $fg $bg $p.c4 $TINT_DIFF_CHANGE)
        diff_text: (tint-under $fg $bg $p.c4 $TINT_DIFF_TEXT)
        diff_add_text: (tint-under $fg $bg $p.c2 $TINT_DIFF_TEXT)
        diff_delete_text: (tint-under $fg $bg $p.c1 $TINT_DIFF_TEXT)
        accent_text: (text-on (do $text $p.c4) $bg)
    }
    $roles | merge $syntax | update cells { rgb-to-hex --prefix "#" } | insert light ($bg | is-light)
}
