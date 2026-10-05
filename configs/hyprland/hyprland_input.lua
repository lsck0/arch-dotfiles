hl.config({
    input = {
        kb_layout = "de",
        -- ^ ` ' type immediately
        kb_variant = "nodeadkeys",
        kb_options = "ctrl:nocaps",
        follow_mouse = 1,
        sensitivity = 0.1,
        touchpad = {
            natural_scroll = true,
            disable_while_typing = true,
            tap_to_click = true,
            drag_lock = true,
            scroll_factor = 0.5,
        },
        tablet = {
            -- confine the virtual pen (configs/tablet/tablet-driver.py) to DP-2; set globally not per-device because the compositor's "-1" suffix on the two pen interfaces is unstable, see configs/tablet/
            output = "DP-2",
        },
    },
})
