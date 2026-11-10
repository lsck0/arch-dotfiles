# A profile line's mode flag, shared by the apply (own profiles) and aa (manual modes): the old complain or
# unconfined flag goes, the new one joins the flags or, on a line without flags, gets its own flags=().

# the brace opening a profile's body, at the end of its line
const BODY_OPEN = '\s*\{\s*$'

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
