use module.nu *

export const meta = {deps: [desktop/chromium]}

def data-dir []: nothing -> path {
    $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join capgemini chromium
}

# arc's sign-in bounces through zpa-auth.net, zscaler and pingfederate with SameSite=None cookies, third-party once
# embedded; restore_on_startup 1 carries pingfederate's session-only PF cookie across restarts
def preferences-edits []: nothing -> list<record> {
    open site-settings.json | items {|kind, sites|
        $sites | each {|site| json-set [profile content_settings exceptions $kind $"($site),*"] {setting: 1} }
    } | flatten | append [(json-set [session restore_on_startup] 1) (json-set [credentials_enable_service] true)]
}

export def link [cfg: record] {
    if not (profile-has work) { return [] }
    let apps = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join applications
    # chromium rewrites Preferences on exit, so this lands only while it is closed
    let running = ps --long | any {|p| $p.command =~ $"--user-data-dir=(data-dir)\( |$\)" }
    [
        (link-commands capgemini.nu)
        # a per-user copy: Exec needs the absolute path, ~/.local/bin is not on every session's PATH
        (file-render capgemini.desktop ($apps | path join capgemini.desktop) {HOME: $nu.home-dir})
    ] | append (if $running { [] } else { [(json-merge (data-dir | path join Default Preferences) (preferences-edits))] })
}
