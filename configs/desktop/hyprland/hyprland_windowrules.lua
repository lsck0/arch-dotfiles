local global_opacity = 0.95

-- their app-drawn menus are windows, only the frame is styleable
for _, class in ipairs({ "^discord$", "^steam$" }) do
    hl.window_rule({ match = { class = class }, rounding = 8 })
end

for _, class in ipairs({
    "^Spotify$",
    "^com.mitchellh.ghostty$",
    "^discord$",
    "^kitty$",
    "^neovide$",
    "^nemo$",
    "^org.kde.dolphin$",
    "^steam$",
}) do
    hl.window_rule({ match = { class = class }, opacity = global_opacity })
end

hl.window_rule({
    match = {
        initial_title = "^Discord Popout$",
    },
    opacity = 1,
})

-- center file pickers
hl.window_rule({
    match = {
        class = "xdg-desktop-portal-gtk",
        title = "^(Open.*Files?|Save.*Files?|All Files|Save)",
    },
    float = true,
    center = true,
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
    "^org.kde.dolphin$",
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

-- unreal's slate child windows (menus, drag previews) tile tiny and mispositioned; float them at their own size, keep the main editor tiled
hl.window_rule({
    match = {
        class = "^UnrealEditor$",
    },
    float = true,
})

hl.window_rule({
    match = {
        title = ".* Unreal Editor$",
    },
    float = false,
})

hl.layer_rule({
    name = "quickshell-notifications-no-anim",
    match = {
        namespace = "^quickshell-notifications$",
    },
    no_anim = true,
})
