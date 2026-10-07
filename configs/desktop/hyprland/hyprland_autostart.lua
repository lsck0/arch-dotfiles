hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm finalize")

    -- the shell expands $DOTFILES: concatenating an unset getenv would abort this hook before hypridle
    hl.exec_cmd("uwsm app -- $DOTFILES/configs/desktop/quickshell/restart.sh")
    hl.exec_cmd("uwsm app -- /usr/lib/polkit-kde-authentication-agent-1")
    hl.exec_cmd("uwsm app -- hypridle")

    -- no hyprpm reload here: it raced manual_link.sh's own and unloaded plugins
    hl.exec_cmd("uwsm app -- $DOTFILES/configs/desktop/hyprland/manual_link.sh")
    hl.exec_cmd("uwsm app -- $DOTFILES/configs/desktop/shimoji/manual_link.sh")

    hl.exec_cmd("xhost +SI:localuser:root")
    if require("platform").laptop then
        hl.exec_cmd("brightnessctl --device=tpacpi::kbd_backlight set 2")
    end
end)
