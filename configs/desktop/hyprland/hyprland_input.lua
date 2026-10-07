-- luca's german layout; a guest's own from the x11 keymap configs/base/locale/link.sh sets with localectl
local DEFAULT_LAYOUT = "de"
local X11_KEYBOARD_CONF = "/etc/X11/xorg.conf.d/00-keyboard.conf"

local kb_layout, kb_variant = DEFAULT_LAYOUT, "nodeadkeys"
local f = io.open(X11_KEYBOARD_CONF, "r")
if f then
    local conf = f:read("a")
    f:close()
    local layout = conf:match('"XkbLayout"%s+"([^"]*)"')
    if layout and layout ~= DEFAULT_LAYOUT then
        kb_layout, kb_variant = layout, conf:match('"XkbVariant"%s+"([^"]*)"') or ""
    end
end

hl.config({
    input = {
        kb_layout = kb_layout,
        -- ^ ` ' type immediately
        kb_variant = kb_variant,
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
            -- confine the virtual pen (configs/hardware/tablet/tablet-driver.py) to DP-2; set globally not per-device because the compositor's "-1" suffix on the two pen interfaces is unstable, see configs/hardware/tablet/
            output = "DP-2",
        },
    },
})
