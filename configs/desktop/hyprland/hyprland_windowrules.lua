local platform = require("platform")
local style = require("style")

-- steam drops its toasts on whatever monitor it thinks is primary
hl.window_rule({
    match = { title = "^notificationtoasts" },
    float = true,
    monitor = platform.main_monitor,
})

for _, class in ipairs({ "^[Ss]potify$", "^discord$" }) do
    hl.window_rule({ match = { class = class }, opacity = style.opacity_surface })
end

for _, class in ipairs({
    "^neovide$",
    "^nemo$",
    "^(org.kde.)?dolphin$",
    "^steam$",
}) do
    hl.window_rule({ match = { class = class }, opacity = style.opacity })
end

hl.window_rule({
    match = {
        initial_title = "^Discord Popout$",
    },
    opacity = 1,
})

hl.window_rule({
    match = {
        class = "xdg-desktop-portal-gtk",
        title = "^(Open.*Files?|Save.*Files?|All Files|Save)",
    },
    float = true,
    center = true,
})

hl.window_rule({ match = { class = "^notes-scratch$" }, float = true, center = true, size = "900 600" })

hl.window_rule({
    match = { class = "^omarchy-share-picker$" },
    float = true,
    center = true,
    size = "1150 750",
})

hl.window_rule({
    match = {
        title = "^wayland-boomer$",
    },
    float = true,
    monitor = "0",
    move = "0 0",
    no_anim = true,
})

for _, class in ipairs({
    "^nemo$",
    "^(org.kde.)?dolphin$",
    "^io.missioncenter.MissionCenter$",
    "^org.pulseaudio.pavucontrol$",
}) do
    hl.window_rule({ match = { class = class }, float = true, size = "1080 720" })
end

hl.window_rule({
    match = {
        class = "^steam$",
    },
    float = true,
})

hl.window_rule({
    match = {
        title = "^Steam$",
    },
    float = false,
})

hl.window_rule({
    match = {
        title = "^gnyame$",
    },
    float = true,
})

hl.window_rule({
    match = {
        class = "^[Ww]aydroid.*$",
    },
    float = true,
})

-- median xl inside gamescope (gaming/d2launcher): floats at a 4:3 size, 80% of the monitor's height; the game
-- scales with every resize, bars fill the rest
hl.window_rule({
    match = {
        class = "^gamescope$",
        title = "^Diablo II$",
    },
    float = true,
    center = true,
    size = "monitor_h*1.0667 monitor_h*0.8",
})

-- unreal's slate child windows (menus, drag previews) tile tiny and mispositioned
hl.window_rule({
    match = {
        class = "^UnrealEditor$",
    },
    float = true,
})

-- floating, they map before the output scale is known and render scaled up and clipped
hl.window_rule({
    match = {
        class = "^UnrealEditor$",
        title = "^(.* - Unreal Editor|Unreal Engine [0-9.]+)$",
    },
    float = false,
})

-- the message log it opens after a load with warnings maps at 60x30 under the float rule above; give it a real size
hl.window_rule({
    match = {
        class = "^UnrealEditor$",
        title = "^Message Log$",
    },
    size = "1200 700",
    center = true,
})

-- slurp's overlay, unanimated: grim captures right after it exits, a fade-out would still show the region border
hl.layer_rule({
    name = "slurp-no-anim",
    match = {
        namespace = "^selection$",
    },
    no_anim = true,
})

hl.layer_rule({
    name = "quickshell-notifications-no-anim",
    match = {
        namespace = "^quickshell-notifications$",
    },
    no_anim = true,
})

hl.layer_rule({
    name = "quickshell-blur",
    match = {
        namespace = "^quickshell-(bar|panel-.+|osd|notifications|alert|appsearch|clipboard|powermenu|overview|image-selector|reminders|network-qr|network-speedtest|disk-speedtest|settings|tasks|notes)$",
    },
    blur = true,
    ignore_alpha = 0.3,
})
