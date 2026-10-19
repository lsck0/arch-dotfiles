#!/usr/bin/env -S nu --no-config-file
# a running spotify takes a new theme or patch over its devtools socket, which spotify-launch.nu opens on loopback

export const DEVTOOLS_PORT = 9233
const PAGE = '^https://xpui\.app\.spotify\.com/'
# re-fetching spicetify's two stylesheets recolours in place, without a reload that would drop the open view
const CSS_RELOAD = "document.querySelectorAll('link.userCSS').forEach(l => l.href = l.href.split('?')[0] + '?' + Date.now())"
const PAGE_RELOAD = "location.reload()"

def devtools-eval [expression: string]: nothing -> nothing {
    let pages = try { http get --max-time 1sec $"http://127.0.0.1:($DEVTOOLS_PORT)/json/list" } catch { return }
    let page = $pages | where type == page and url =~ $PAGE | get --optional 0
    if $page == null { return }
    {id: 1, method: Runtime.evaluate, params: {expression: $expression}} | to json --raw
    | ^websocat --one-message --no-close $page.webSocketDebuggerUrl | complete | ignore
}

# --page after a patch, whose js only a reload runs
def main [--page]: nothing -> nothing {
    if $page {
        devtools-eval $PAGE_RELOAD
        return
    }
    # before the first patch there is nothing to refresh; the patch itself picks up the theme
    if (which spicetify | is-empty) { return }
    let refreshed = do { ^spicetify -n -q refresh } | complete
    if $refreshed.exit_code == 0 { devtools-eval $CSS_RELOAD }
}
