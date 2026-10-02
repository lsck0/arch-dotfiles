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
            -- Confine the pen to the right-hand screen. Without this the pen
            -- is stretched across the whole layout, so half the tablet lands
            -- on DP-1. The full tablet surface maps to the full output, which
            -- is a slight horizontal stretch: the tablet is 205x137mm (3:2)
            -- and the output is 16:9.
            --
            -- Set globally rather than per device on purpose. The tablet
            -- reports two pen interfaces and the compositor disambiguates
            -- them by appending "-1" in enumeration order, so a device rule
            -- can land on the wrong one. See configs/tablet/.
            --
            -- The pen that reaches the compositor is the virtual one
            -- published by configs/tablet/tablet-driver.py, not the kernel's.
            -- The firmware squeezes X into the upper half of its declared
            -- range, so mapping the kernel device to an output puts half the
            -- surface in a dead zone against the screen edge. The driver
            -- rescales it, and only then is this binding bijective.
            output = "DP-2",
        },
    },
})
