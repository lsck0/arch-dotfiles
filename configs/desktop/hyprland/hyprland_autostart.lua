hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm finalize")

    hl.exec_cmd("uwsm app -- " .. os.getenv("HOME") .. "/projects/arch-dotfiles/configs/desktop/quickshell/restart.sh")
    hl.exec_cmd("uwsm app -- /usr/lib/polkit-kde-authentication-agent-1")
    hl.exec_cmd("uwsm app -- hypridle")

    -- no hyprpm reload here: it raced manual_link.sh's own and unloaded plugins
    hl.exec_cmd("uwsm app -- ~/projects/arch-dotfiles/configs/desktop/hyprland/manual_link.sh")
    hl.exec_cmd("uwsm app -- ~/projects/arch-dotfiles/configs/desktop/shimoji/manual_link.sh")

    hl.exec_cmd("xhost +SI:localuser:root")
    if require("platform").laptop then
        hl.exec_cmd("brightnessctl --device=tpacpi::kbd_backlight set 2")
    end
end)
