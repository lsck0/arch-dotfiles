hl.on("hyprland.start", function()
    -- the hl.env scales too, so quickshell.service and every app it launches see what the compositor's children see
    hl.exec_cmd("uwsm finalize GDK_SCALE QT_AUTO_SCREEN_SCALE_FACTOR")

    -- quickshell's unit waits for the finalize above
    hl.exec_cmd("systemctl --user start quickshell.service")
    hl.exec_cmd("uwsm app -s s -- /usr/lib/polkit-kde-authentication-agent-1")

    -- the shell expands $DOTFILES (an unset getenv would abort this hook); no hyprpm reload here, it races plugins.nu's
    hl.exec_cmd("uwsm app -s b -- $DOTFILES/configs/desktop/hyprland/plugins.nu")
    hl.exec_cmd("uwsm app -s b -- $DOTFILES/configs/desktop/shimoji/packs.nu")

    hl.exec_cmd("xhost +SI:localuser:root")
    local backlight = require("platform").kbd_backlight
    if backlight then
        hl.exec_cmd("brightnessctl --device=" .. backlight .. " set 2")
    end
end)
