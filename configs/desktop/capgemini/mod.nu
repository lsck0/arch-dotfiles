use module.nu *

export const meta = {deps: [desktop/chromium]}

def data-dir []: nothing -> path {
    $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join capgemini chromium
}

# exceptions in this profile only, the managed policy (desktop/chromium) is every profile's. arc is zscaler private
# access: its sign-in bounces through zpa-auth.net, zscaler and pingfederate with SameSite=None cookies, third-party
# once the portal embeds an app or the isolation session; an exception also spares those bounce-only sites chromium's
# bounce tracking cleanup. popups for the portal's app tabs, clipboard only for the isolation stream, durable storage
# keeps microsoft 365's indexeddb out of eviction. restore_on_startup 1 carries session-only cookies (pingfederate's PF)
# across restarts; the password manager saves into the login keyring (capgemini.nu), the managed policy still wins
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
