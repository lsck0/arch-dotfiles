hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm finalize")

    -- long-running apps -> scoped systemd units
    -- hyprsunset's daemon. It was installed and bound to SHIFT+brightness
    -- for raw gamma nudges, but nothing ever STARTED it, so those two
    -- keybinds failed silently ("Couldn't connect to ....hyprsunset.sock")
    -- for as long as they existed. Starting it here fixes them and gives
    -- toggles/toggle-nightlight.sh something to talk to. Started neutral
    -- (6000K) so it changes nothing until asked.
    --
    -- --gamma_max 150: hyprsunset's default ceiling is 100, which is also
    -- its starting value, so SHIFT+BrightnessUp ("gamma +5") could never do
    -- anything at all — only the Down half of that pair worked. Raising the
    -- ceiling makes the bind useful in both directions.
    hl.exec_cmd("uwsm app -- hyprsunset -t 6000 --gamma_max 150")

    -- awww-daemon lived here until 2026-09-02. quickshell's
    -- plugins/background/Background.qml paints the wallpaper now and
    -- does its own crossfade; running both was two renderers racing for
    -- the same layer. Verified: with awww-daemon killed the wallpaper
    -- still renders.
    -- copyq was autostarted here until 2026-09-03. It duplicated
    -- quickshell's own clipboard plugin: both watched the selection and
    -- both stored every copy (verified — one probe string landed in
    -- both histories). Retired for the same reason waybar and mako were.
    --
    -- The roadmap hedged on this because copyq supposedly had
    -- "persistent storage across reboots" the plugin lacked. That is
    -- wrong: the plugin persists to ~/.local/state/quickshell/
    -- clipboard-history.json (500 entries) and additionally skips
    -- password-manager content, which is why the hedge did not survive.
    --
    -- The package is still installed and its data untouched, so `copyq`
    -- by hand still opens the old 200-item history if you want it back.
    hl.exec_cmd("uwsm app -- hypridle")
    -- mako replaced by configs/quickshell/plugins/notifications/Service.qml
    -- (native org.freedesktop.Notifications daemon) -- see TODO.md. Left
    -- installed (see install.sh) as a manual fallback, just not autostarted.
    hl.exec_cmd("uwsm app -- /usr/lib/polkit-kde-authentication-agent-1")
    hl.exec_cmd("uwsm app -- " .. os.getenv("HOME") .. "/projects/arch-dotfiles/configs/quickshell/restart.sh") -- replaces waybar
    hl.exec_cmd("uwsm app -- ~/projects/arch-dotfiles/scripts/watch-monitors.sh")

    -- oneshots, leave bare
    hl.exec_cmd("hyprpm reload")
    hl.exec_cmd("xhost + local:")
    hl.exec_cmd("xhost +SI:localuser:root")
    -- The systemd service (kbd-backlight-max.service) sets this at boot,
    -- but systemd-backlight restores the saved value (often 0) after it,
    -- and the kernel default is also 0. Re-apply when Hyprland starts so
    -- the keyboard backlight is always on for the graphical session.
    hl.exec_cmd("brightnessctl --device=tpacpi::kbd_backlight set 2")

    -- walker's service (and `elephant`, its data provider, which had to
    -- start first) lived here until 2026-09-02. Both went with walker:
    -- quickshell's launcher is part of the shell and needs no daemon.
end)
