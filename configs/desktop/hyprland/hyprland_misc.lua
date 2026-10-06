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
        -- 2 not 1: only scan out windows that request it, so a maximized app (unreal editor) does not flicker flipping scanout against its child windows; grading stays in the gamma lut
        direct_scanout = 2,
    },
})
