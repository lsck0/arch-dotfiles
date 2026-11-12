# What the apply (mod.nu) and aa share: where own profiles and apparmor.d's sources live, a profile line's mode.

export const MARKER = "# managed by arch-dotfiles/apparmor"
# an own profile's file: never the bare name, which the apparmor package owns and aa-install's overwrite.d disables
export const OWN_SUFFIX = ".dotfiles"
export const ETC = "/etc/apparmor.d"
export const SOURCE = "/usr/share/apparmor.d"
# the brace opening a profile's body, at the end of its line
const BODY_OPEN = '\s*\{\s*$'

# apparmor.d's profile sources, without its abstractions and tunables; none when apparmor.d is missing.
export def upstream-files [source: path = $SOURCE]: nothing -> list<path> {
    glob $"($source)/**/*" --no-dir | where not ($it =~ '/(abstractions|tunables)/')
}

# The old complain or unconfined flag goes, the new one joins the flags or, on a line without flags, gets its own
# flags=(); enforce is the absence of both.
export def profile-mode [mode: string]: string -> string {
    let bare = $in
        | str replace --regex '\s*flags=\((complain|unconfined)\)' ''
        | str replace --regex 'flags=\((complain|unconfined),' 'flags=('
    if $mode not-in [complain unconfined] { return $bare }
    if ($bare =~ 'flags=\(') {
        $bare | str replace 'flags=(' $"flags=\(($mode),"
    } else {
        $bare | str replace --regex $BODY_OPEN $" flags=\(($mode)) {"
    }
}

# A whole profile file with every profile line in this mode.
export def text-mode [mode: string]: string -> string {
    lines | each {|l| if ($l | str starts-with "profile ") { $l | profile-mode $mode } else { $l } }
    | str join "\n" | $"($in)\n"
}
