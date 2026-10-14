local platform = require("platform")

hl.config({
    input = {
        kb_layout = platform.keyboard.layout,
        kb_variant = platform.keyboard.variant,
        kb_options = platform.keyboard.options,
        follow_mouse = 1,
        sensitivity = platform.pointer.sensitivity,
        touchpad = {
            natural_scroll = platform.pointer.natural_scroll,
            disable_while_typing = true,
            tap_to_click = true,
            drag_lock = true,
            scroll_factor = 0.5,
        },
        tablet = {
            -- confine the virtual pen (configs/base/tablet/tablet-driver.py) to the main monitor; set globally not per-device because the compositor's "-1" suffix on the two pen interfaces is unstable, see configs/base/tablet/
            output = platform.main_monitor,
        },
    },
})
