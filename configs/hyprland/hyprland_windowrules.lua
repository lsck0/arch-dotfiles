local global_opacity = 0.95
hl.window_rule({
    match = {
        class = "^Spotify$",
    },
    opacity = global_opacity,
})

hl.window_rule({
    match = {
        class = "^com.mitchellh.ghostty$",
    },
    opacity = global_opacity,
})

hl.window_rule({
    match = {
        class = "^discord$",
    },
    opacity = global_opacity,
})

hl.window_rule({
    match = {
        class = "^kitty$",
    },
    opacity = global_opacity,
})

hl.window_rule({
    match = {
        class = "^nemo$",
    },
    opacity = global_opacity,
})

hl.window_rule({
    match = {
        class = "^wofi$",
    },
    opacity = global_opacity,
})

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

-- pavucontrol
hl.window_rule({
    match = {
        class = "^org.pulseaudio.pavucontrol$",
    },
    float = true,
    size = "1080 720",
})

-- wayland-boomer
hl.window_rule({
    match = {
        title = "^wayland-boomer$",
    },
    float = true,
    monitor = "0",
    move = "0 0",
    no_anim = true,
})

-- nemo
hl.window_rule({
    match = {
        class = "^nemo$",
    },
    float = true,
    size = "1080 720",
})

-- mission control
hl.window_rule({
    match = {
        class = "^io.missioncenter.MissionCenter$",
    },
    float = true,
    size = "1080 720",
})

-- steam
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

-- gnyame
hl.window_rule({
    match = {
        title = "^gnyame$",
    },
    float = true,
})
