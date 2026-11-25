local platform = require("platform")

hl.config({
    input = {
        kb_layout = platform.keyboard.layout,
        kb_variant = platform.keyboard.variant,
        kb_options = platform.keyboard.options,
        repeat_rate = platform.input.repeat_rate,
        repeat_delay = platform.input.repeat_delay,
        numlock_by_default = platform.input.numlock,
        follow_mouse = platform.pointer.follow_mouse,
        -- a new tile reflows the layout under a resting cursor; with refocus on, the next touchpad jitter hands focus to
        -- whatever window now sits there, so a freshly opened terminal loses it. Focus follows only on crossing a border
        mouse_refocus = false,
        sensitivity = platform.pointer.sensitivity,
        accel_profile = platform.pointer.accel_profile,
        left_handed = platform.pointer.left_handed,
        touchpad = {
            natural_scroll = platform.pointer.natural_scroll,
            disable_while_typing = true,
            tap_to_click = platform.input.tap_to_click,
            drag_lock = true,
            scroll_factor = platform.input.scroll_factor,
        },
        tablet = {
            -- set globally: the compositor's "-1" suffix on the two pen interfaces is unstable (configs/base/tablet/)
            output = platform.main_monitor,
        },
    },
})
