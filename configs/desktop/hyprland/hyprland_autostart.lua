hl.on("hyprland.start", function()
    -- the hl.env scales too, so quickshell.service and every app it launches see what the compositor's children see
    hl.exec_cmd("uwsm finalize GDK_SCALE QT_AUTO_SCREEN_SCALE_FACTOR")

    -- the session's own pieces in session.slice (protected, never an oomd pick), not app.slice; quickshell restarts
    -- itself on a crash, its unit waits for the finalize above
    hl.exec_cmd("systemctl --user start quickshell.service")
    hl.exec_cmd("uwsm app -s s -- /usr/lib/polkit-kde-authentication-agent-1")
    hl.exec_cmd("uwsm app -s s -- hypridle")

    -- the shell expands $DOTFILES: concatenating an unset getenv would abort this hook
    -- no hyprpm reload here: it raced manual_link.sh's own and unloaded plugins
    hl.exec_cmd("uwsm app -s b -- $DOTFILES/configs/desktop/hyprland/manual_link.sh")
    hl.exec_cmd("uwsm app -s b -- $DOTFILES/configs/desktop/shimoji/manual_link.sh")

    hl.exec_cmd("xhost +SI:localuser:root")
    if require("platform").laptop then
        hl.exec_cmd("brightnessctl --device=tpacpi::kbd_backlight set 2")
    end
end)
