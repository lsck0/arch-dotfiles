hl.config({
    misc = {
        -- A QML error while the session is locked is an unrecoverable
        -- lockout without this: it lets a crashed session-lock client be
        -- restored instead of leaving the session sealed. Locking is
        -- handled by hyprlock, not quickshell, but this stays on as cheap
        -- insurance against any future in-process lock surface.
        allow_session_lock_restore = true,
        animate_manual_resizes = true,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        enable_swallow = false,
        focus_on_activate = true,
        force_default_wallpaper = 0,
        key_press_enables_dpms = true,
        mouse_move_enables_dpms = true,
        vrr = 2,
    },
})
