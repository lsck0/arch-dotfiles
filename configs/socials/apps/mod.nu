use module.nu *

export const meta = {packages: {pacman: [chatuino-bin hexchat proton-mail-bin proton-meet-bin signal-desktop zapzap]}}

const ZAPZAP_SEEN = {
    website: {open_page: "false"}
    onboarding: {initial_setup_completed: "true"}
    notification: {donation_message: "true"}
}

export def link [cfg: record] {
    [
        (ini-merge (xdg config ZapZap ZapZap.conf) $ZAPZAP_SEEN)
        # as element: under hyprland electron falls back to the basic store, the database key in plain config.json
        (desktop-override signal.desktop {
            $in | str replace --all --regex '(?m)^(Exec=signal-desktop) ' '$1 --password-store=gnome-libsecret '
        })
    ]
}
