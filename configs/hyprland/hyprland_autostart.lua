hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm finalize")

    hl.exec_cmd("uwsm app -- hyprsunset -t 6000 --gamma_max 150")

    hl.exec_cmd("uwsm app -- hypridle")
    hl.exec_cmd("uwsm app -- /usr/lib/polkit-kde-authentication-agent-1")
    hl.exec_cmd("uwsm app -- " .. os.getenv("HOME") .. "/projects/arch-dotfiles/configs/quickshell/restart.sh") -- replaces waybar
    hl.exec_cmd("uwsm app -- ~/projects/arch-dotfiles/scripts/watch-monitors.sh")

    -- First-boot-only setup (hyprpm plugins, shimeji imports). Both scripts
    -- no-op when their ~/.local/state marker exists.
    hl.exec_cmd("uwsm app -- ~/projects/arch-dotfiles/configs/hypr/manual_link.sh")
    hl.exec_cmd("uwsm app -- ~/projects/arch-dotfiles/configs/shimoji/manual_link.sh")

    hl.exec_cmd("hyprpm reload")
    hl.exec_cmd("xhost + local:")
    hl.exec_cmd("xhost +SI:localuser:root")
    hl.exec_cmd("brightnessctl --device=tpacpi::kbd_backlight set 2")
end)
