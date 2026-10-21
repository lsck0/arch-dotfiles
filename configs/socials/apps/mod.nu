use module.nu *

export const meta = {packages: {pacman: [chatuino-bin hexchat proton-mail-bin proton-meet-bin signal-desktop zapzap]}}

# zapzap's first start opens its website in the browser, then a setup wizard, later a donation toaster; each is a
# QSettings flag it reads back
const ZAPZAP_SEEN = {
    website: {open_page: "false"}
    onboarding: {initial_setup_completed: "true"}
    notification: {donation_message: "true"}
}

export def link [cfg: record] {
    let config = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config)
    ini-merge ($config | path join ZapZap ZapZap.conf) $ZAPZAP_SEEN
}
