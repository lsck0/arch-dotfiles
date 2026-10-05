hl.config({
    misc = {
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
    render = {
        -- a lone fullscreen window skips composition; grading lives in the gamma LUT so it still applies, vrr keeps it tear-free
        direct_scanout = 1,
    },
})
