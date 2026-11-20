local platform = require("platform")
local style = require("style")

-- steam drops its toasts on whatever monitor it thinks is primary
hl.window_rule({ match = { title = "^notificationtoasts" }, float = true, monitor = platform.main_monitor })

for _, class in ipairs({ "^[Ss]potify$", "^discord$", "^nemo$", "^(org.kde.)?dolphin$" }) do
    hl.window_rule({ match = { class = class }, opacity = style.opacity_window })
end
-- steam's library and store art turn to noise over the wallpaper at the shared opacity
hl.window_rule({ match = { class = "^steam$" }, opacity = 0.9 })

-- a link opened from another app takes you to the browser's workspace; misc.focus_on_activate stays off so no other
-- window pulls focus by asking
hl.window_rule({ match = { class = "^(firefox|chromium)$" }, focus_on_activate = true })

hl.window_rule({ match = { initial_title = "^Discord Popout$" }, opacity = 1 })

-- awakened poe trade: a pinned overlay above the game
hl.window_rule({
    match = { class = "^awakened-poe-trade$" },
    float = true,
    pin = true,
    border_size = 0,
    no_shadow = true,
    no_anim = true,
    opacity = 1,
})

-- every window of the gtk portal is a dialog (file chooser, app chooser, access prompt), whatever its language
hl.window_rule({ match = { class = "^xdg-desktop-portal-gtk$" }, float = true, center = true })

-- firefox, chromium and firefox in German
hl.window_rule({
    match = { title = "^(Picture[- ]in[- ][Pp]icture|Bild-im-Bild)$" },
    float = true,
    pin = true,
    keep_aspect_ratio = true,
})

hl.window_rule({ match = { class = "^notes-scratch$" }, float = true, center = true, size = "900 600" })

hl.window_rule({ match = { class = "^omarchy-share-picker$" }, float = true, center = true, size = "1150 750" })

-- boomer's frozen screenshot spans every monitor. Its first frame comes up where and as large as a new float does,
-- before any move reaches it, which flashed a shifted picture: it maps invisible, is placed at the layout's top-left,
-- and shows once that has landed (no static position fits every layout)
local BOOMER_SHOW_MS = 60

hl.window_rule({ match = { title = "^wayland-boomer$" }, float = true, no_anim = true, opacity = 0 })

hl.on("window.open", function(window)
    if window.title ~= "wayland-boomer" then
        return
    end
    local x, y
    for _, monitor in ipairs(hl.get_monitors()) do
        if not monitor.name:match("^HEADLESS%-") then
            x = math.min(x or monitor.position.x, monitor.position.x)
            y = math.min(y or monitor.position.y, monitor.position.y)
        end
    end
    local target = "address:" .. window.address
    hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = target }))
    hl.timer(function()
        hl.dispatch(hl.dsp.window.set_prop({ window = target, prop = "opacity", value = 1 }))
    end, { timeout = BOOMER_SHOW_MS, type = "oneshot" })
end)

for _, class in ipairs({
    "^nemo$",
    "^(org.kde.)?dolphin$",
    "^io.missioncenter.MissionCenter$",
    "^org.pulseaudio.pavucontrol$",
}) do
    hl.window_rule({
        match = { class = class },
        float = true,
        center = true,
        size = "min(1080,monitor_w*0.8) min(720,monitor_h*0.8)",
    })
end

-- an xwayland dialog with no parent: maps at the global origin, which is another output's corner when scaled
hl.window_rule({ match = { class = "^Hexchat$", title = "^Network List - HexChat$" }, center = true })

for _, match in ipairs({ { class = "^steam$" }, { title = "^gnyame$" }, { class = "^[Ww]aydroid.*$" } }) do
    hl.window_rule({ match = match, float = true })
end
-- steam's main window tiles, its dialogs float
hl.window_rule({ match = { title = "^Steam$" }, float = false })

hl.window_rule({
    match = { class = "^gamescope$", title = "^Diablo II$" },
    float = true,
    center = true,
    size = "monitor_h*1.0667 monitor_h*0.8",
})

-- unreal's slate child windows (menus, drag previews) tile tiny and mispositioned
hl.window_rule({ match = { class = "^UnrealEditor$" }, float = true })

-- floating, they map before the output scale is known and render scaled up and clipped
hl.window_rule({
    match = { class = "^UnrealEditor$", title = "^(.* - Unreal Editor|Unreal Engine [0-9.]+)$" },
    float = false,
})

-- the message log it opens after a load with warnings maps at 60x30 under the float rule above; give it a real size
hl.window_rule({ match = { class = "^UnrealEditor$", title = "^Message Log$" }, size = "1200 700", center = true })

-- unanimated: grim captures right after slurp's overlay exits, a fade-out would still show the region border
hl.layer_rule({ name = "slurp-no-anim", match = { namespace = "^selection$" }, no_anim = true })
-- the shell animates its own surfaces; a compositor slide or fade on top would play every open twice
hl.layer_rule({ name = "quickshell-no-anim", match = { namespace = "^quickshell-" }, no_anim = true })

hl.layer_rule({
    name = "quickshell-blur",
    match = {
        namespace = "^quickshell-(bar|panel-.+|osd|notifications|alert|appsearch|clipboard|powermenu|overview|image-picker|reminders|wifiqr|speedtest|settings|tasks|desktop-widgets|polkit|scrim)$",
    },
    blur = true,
    blur_popups = true,
    ignore_alpha = 0.3,
    -- every shell surface takes the cached wallpaper blur, whatever is open behind it: one glass, and the backdrop the
    -- opacities are computed for
    xray = true,
})

-- the scrim under an overlay card dims and blurs the live screen; it lies under the card's own surface
-- the scrim has no glow halos: a low threshold blurs it from the first frame of its fade to the last, not from halfway
hl.layer_rule({
    name = "quickshell-scrim",
    match = { namespace = "^quickshell-scrim$" },
    xray = false,
    order = 1,
    ignore_alpha = 0.02,
})
