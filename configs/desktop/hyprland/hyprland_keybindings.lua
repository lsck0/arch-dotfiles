local mod = "SUPER"

local function shell_bin(name)
    return "~/.local/bin/" .. name
end

local function quickshell_call(target, fn)
    return hl.dsp.exec_cmd("quickshell ipc -p ~/.config/quickshell call " .. target .. " " .. fn)
end

local function quickshell_toggle(target)
    return quickshell_call(target, "toggle")
end

-- An app gets its own scope in app.slice: out of the compositor's protected cgroup, an oomd candidate on its own.
local function app(cmd)
    return hl.dsp.exec_cmd("uwsm-app -- " .. cmd)
end

local function helper(cmd)
    return hl.dsp.exec_cmd("uwsm-app -s b -- " .. cmd)
end

local function media_key(action)
    return hl.dsp.exec_cmd(shell_bin("media-key") .. " " .. action)
end

local color_grading = "$DOTFILES/configs/desktop/color-grading/color-grading.py"

-- Obs hotkeys only fire while obs is focused on wayland; timeout covers obs closed.
local function obs_command(cmd)
    return hl.dsp.exec_cmd(
        'echo \'{"cmd":"'
            .. cmd
            .. "\"}' | timeout 5 "
            .. "$DOTFILES/configs/desktop/quickshell/plugins/bar/widgets/obs-status.nu >/dev/null"
    )
end

hl.bind(mod .. " + SHIFT + e", quickshell_toggle("powermenu"), { description = "power menu" })
hl.bind(
    mod .. " + SHIFT + s",
    hl.dsp.exec_cmd("$DOTFILES/configs/desktop/hyprland/screenshot-region.nu"),
    { description = "screenshot a region to the clipboard" }
)
hl.bind(
    mod .. " + SHIFT + PRINT",
    hl.dsp.exec_cmd("grim -o \"$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name')\" - | wl-copy"),
    { description = "screenshot the focused monitor to the clipboard" }
)
hl.bind(
    "CTRL + SHIFT + ALT + s",
    hl.dsp.exec_cmd(
        'grim -g "$(hyprctl -j activewindow | jq -r \'select(.at and .size) | "\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])"\')" - | wl-copy'
    ),
    { description = "screenshot the active window to the clipboard" }
)
hl.bind(mod .. " + SHIFT + y", hl.dsp.exec_cmd("shimejictl stop"), { description = "stop the desktop mascots" })
hl.bind(mod .. " + F9", obs_command("saveReplay"), { description = "obs: save the replay buffer" })
hl.bind(mod .. " + SHIFT + F9", obs_command("toggleReplay"), { description = "obs: start or stop the replay buffer" })
-- mangohud's own toggle_hud never sees a key on wayland (gaming/mangohud); non-consuming so editors keep shift+f12
hl.bind(
    "SHIFT + F12",
    hl.dsp.exec_cmd(shell_bin("mangohud-toggle")),
    { non_consuming = true, description = "show or hide the mangohud overlay" }
)
hl.bind(mod .. " + Tab", quickshell_call("overview", "open"), { description = "overview of workspaces and windows" })
hl.bind(
    mod .. " + Return",
    hl.dsp.exec_cmd(
        "gdbus call --session --timeout 5 --dest com.mitchellh.ghostty --object-path /com/mitchellh/ghostty --method org.gtk.Actions.Activate new-window '[]' '{}' || uwsm-app -- kitty"
    ),
    { description = "terminal (ghostty, kitty when ghostty is down)" }
)
hl.bind(mod .. " + SHIFT + Return", app("kitty"), { description = "kitty terminal" })
hl.bind(mod .. " + a", app("firefox"), { description = "firefox" })
hl.bind(mod .. " + SHIFT + a", app("qutebrowser"), { description = "qutebrowser" })
hl.bind(mod .. " + d", quickshell_toggle("appsearch"), { description = "app launcher" })
hl.bind(
    mod .. " + ALT + d",
    hl.dsp.exec_cmd(
        "cmd=$(bash -c 'compgen -c' | sort -u | $DOTFILES/configs/desktop/hyprland/picker.nu -p run) && uwsm-app -- sh -c \"$cmd\""
    ),
    { description = "run a command from $PATH (the launcher while quickshell is down)" }
)
hl.bind(
    mod .. " + SHIFT + r",
    hl.dsp.exec_cmd("$DOTFILES/configs/desktop/quickshell/restart.nu"),
    { description = "restart quickshell" }
)
-- loginctl, so hypridle's lock_cmd picks quickshell or hyprlock
hl.bind(mod .. " + Escape", hl.dsp.exec_cmd("loginctl lock-session"), { description = "lock the screen" })
hl.bind(mod .. " + m", quickshell_call("discord", "toggleMute"), { description = "mute or unmute discord" })
hl.bind(mod .. " + e", app("dolphin"), { description = "file manager (dolphin)" })
hl.bind(mod .. " + n", app("neovide"), { description = "editor (neovide)" })
hl.bind(
    mod .. " + SHIFT + n",
    app(
        "kitty --class notes-scratch sh -c "
            .. '\'d="$HOME/sync/notes"; mkdir -p "$d"; exec "${EDITOR:-nvim}" "$d/notes.md"\''
    ),
    { description = "notes pad in a floating editor" }
)
hl.bind(mod .. " + o", quickshell_toggle("tasks"), { description = "tasks and notes panel" })
hl.bind(mod .. " + comma", quickshell_toggle("settings"), { description = "settings window" })
hl.bind(
    mod .. " + p",
    hl.dsp.exec_cmd("hyprpicker | tr -d '\\n' | wl-copy"),
    { description = "pick a screen color to the clipboard" }
)
hl.bind(mod .. " + t", quickshell_call("shell", "summon panel.reminders {}"), { description = "timer and pomodoro" })
hl.bind(mod .. " + SHIFT + t", app("missioncenter"), { description = "system monitor (mission center)" })
hl.bind(mod .. " + w", helper(shell_bin("wallpaper-picker")), { description = "wallpaper picker" })
hl.bind(mod .. " + y", helper("spawn-shimeji"), { description = "spawn a desktop mascot" })
hl.bind(mod .. " + x", app("$DOTFILES/configs/desktop/hyprland/boomer.nu"), { description = "magnifier (boomer)" })

hl.bind(mod .. " + Q", hl.dsp.exec_cmd("$DOTFILES/configs/desktop/hyprland/window-close.nu"), {
    description = "close the window (a gamescope game is killed)",
})
hl.bind(mod .. " + space", hl.dsp.window.float({ action = "toggle" }), { description = "float or tile the window" })
hl.bind(mod .. " + s", hl.dsp.focus({ last = true }), { description = "focus the previous window" })
hl.bind(
    mod .. " + f",
    hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }),
    { description = "fullscreen the window" }
)
hl.bind(mod .. " + v", quickshell_toggle("clipboard"), { description = "clipboard history" })

hl.bind(mod .. " + g", hl.dsp.layout("togglesplit"), { description = "toggle the split direction" })

hl.bind(
    "XF86AudioPlay",
    hl.dsp.exec_cmd("playerctl play-pause"),
    { locked = true, description = "play or pause media" }
)
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true, description = "previous track" })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true, description = "next track" })
hl.bind(
    "XF86AudioMedia",
    hl.dsp.exec_cmd("playerctl play-pause"),
    { locked = true, description = "play or pause media" }
)
hl.bind("XF86AudioStop", hl.dsp.exec_cmd("playerctl stop"), { locked = true, description = "stop media" })
hl.bind("XF86AudioRaiseVolume", media_key("volume-up"), { locked = true, repeating = true, description = "volume up" })
hl.bind(
    "XF86AudioLowerVolume",
    media_key("volume-down"),
    { locked = true, repeating = true, description = "volume down" }
)
hl.bind("XF86AudioMute", media_key("volume-mute"), { locked = true, description = "mute the output" })
hl.bind("XF86AudioMicMute", media_key("mic-mute"), { locked = true, description = "mute the microphone" })

hl.bind(
    "XF86MonBrightnessUp",
    media_key("brightness-up"),
    { locked = true, repeating = true, description = "brightness up" }
)
hl.bind(
    "XF86MonBrightnessDown",
    media_key("brightness-down"),
    { locked = true, repeating = true, description = "brightness down" }
)
hl.bind(
    "SHIFT + XF86MonBrightnessUp",
    hl.dsp.exec_cmd(color_grading .. " set brightness +5"),
    { locked = true, repeating = true, description = "software brightness up (color grading)" }
)
hl.bind(
    "SHIFT + XF86MonBrightnessDown",
    hl.dsp.exec_cmd(color_grading .. " set brightness -5"),
    { locked = true, repeating = true, description = "software brightness down (color grading)" }
)

hl.bind("XF86KbdBrightnessUp", media_key("kbd-backlight-up"), { locked = true, description = "keyboard backlight up" })
hl.bind(
    "XF86KbdBrightnessDown",
    media_key("kbd-backlight-down"),
    { locked = true, description = "keyboard backlight down" }
)
hl.bind(
    "XF86KbdLightOnOff",
    media_key("kbd-backlight-toggle"),
    { locked = true, description = "keyboard backlight on or off" }
)
hl.bind(
    mod .. " + SHIFT + b",
    media_key("kbd-backlight-toggle"),
    { locked = true, description = "keyboard backlight on or off" }
)

-- agent-guard can inhibit the lid switch; then an undocked close locks instead of suspending
hl.bind(
    "switch:on:Lid Switch",
    hl.dsp.exec_cmd(
        "$DOTFILES/configs/desktop/hyprland/lid.nu closed;"
            .. " loginctl show-session -p BlockInhibited --value | grep -qw handle-lid-switch"
            .. " && loginctl show-session -p Docked --value | grep -qx no && loginctl lock-session"
    ),
    { locked = true, description = "lid closed: internal panel off when docked, lock when inhibited and undocked" }
)
hl.bind(
    "switch:off:Lid Switch",
    hl.dsp.exec_cmd("$DOTFILES/configs/desktop/hyprland/lid.nu open"),
    { locked = true, description = "lid opened: internal panel back on" }
)

local DIRECTIONS = {
    { keys = { "h", "Left" }, focus = "left", move = "l" },
    { keys = { "l", "Right" }, focus = "right", move = "r" },
    { keys = { "k", "Up" }, focus = "up", move = "u" },
    { keys = { "j", "Down" }, focus = "down", move = "d" },
}
for _, direction in ipairs(DIRECTIONS) do
    for _, key in ipairs(direction.keys) do
        hl.bind(
            mod .. " + " .. key,
            hl.dsp.focus({ direction = direction.focus }),
            { description = "focus the window " .. direction.focus }
        )
        hl.bind(
            mod .. " + SHIFT + " .. key,
            hl.dsp.window.move({ direction = direction.move }),
            { description = "move the window " .. direction.focus }
        )
        hl.bind(
            mod .. " + CTRL + " .. key,
            hl.dsp.window.move({ into_or_create_group = direction.move }),
            { description = "move the window into the group " .. direction.focus }
        )
    end
end

hl.bind(mod .. " + CTRL + w", hl.dsp.group.toggle(), { description = "group or ungroup the window" })
hl.bind(mod .. " + c", hl.dsp.group.next(), { description = "next window in the group" })

for workspace = 1, 10 do
    local key = tostring(workspace % 10)
    hl.bind(
        mod .. " + " .. key,
        hl.dsp.focus({ workspace = workspace }),
        { description = "focus workspace " .. workspace }
    )
    hl.bind(
        mod .. " + SHIFT + " .. key,
        hl.dsp.window.move({ workspace = workspace }),
        { description = "move the window to workspace " .. workspace }
    )
end

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "move the window with the mouse" })
hl.bind(
    mod .. " + mouse:273",
    hl.dsp.window.resize(),
    { mouse = true, description = "resize the window with the mouse" }
)

local RESIZE_STEP = 30
local RESIZE = {
    { keys = { "l", "Right" }, x = RESIZE_STEP, y = 0 },
    { keys = { "h", "Left" }, x = -RESIZE_STEP, y = 0 },
    { keys = { "k", "Up" }, x = 0, y = -RESIZE_STEP },
    { keys = { "j", "Down" }, x = 0, y = RESIZE_STEP },
}
hl.bind(mod .. " + R", hl.dsp.submap("resize"), { description = "resize mode" })
hl.define_submap("resize", function()
    for _, step in ipairs(RESIZE) do
        for _, key in ipairs(step.keys) do
            hl.bind(
                key,
                hl.dsp.window.resize({ x = step.x, y = step.y, relative = true }),
                { repeating = true, description = "resize the window by " .. RESIZE_STEP .. " px" }
            )
        end
    end

    hl.bind(mod .. " + R", hl.dsp.submap("reset"), { description = "leave resize mode" })
    hl.bind("Escape", hl.dsp.submap("reset"), { description = "leave resize mode" })
end)

local PANELS = {
    { key = "a", panel = "audio-io", name = "audio" },
    { key = "b", panel = "notifications", name = "notifications" },
    { key = "c", panel = "clock", name = "clock and calendar" },
    { key = "d", panel = "display", name = "display" },
    { key = "h", panel = "homelab", name = "homelab" },
    { key = "i", panel = "agents", name = "agents" },
    { key = "m", panel = "media", name = "media" },
    { key = "n", panel = "network", name = "network" },
    { key = "o", panel = "obs", name = "obs" },
    { key = "s", panel = "system", name = "system" },
    { key = "v", panel = "discord", name = "discord voice" },
    { key = "w", panel = "weather", name = "weather" },
}
hl.bind(mod .. " + b", hl.dsp.submap("panels"), { description = "bar panel: then a letter (a n s c ...)" })
hl.define_submap("panels", "reset", function()
    for _, entry in ipairs(PANELS) do
        for _, keys in ipairs({ entry.key, mod .. " + " .. entry.key }) do
            hl.bind(
                keys,
                quickshell_call("bar", "toggle " .. entry.panel),
                { description = "bar panel: " .. entry.name }
            )
        end
    end
    hl.bind("catchall", hl.dsp.submap("reset"), { description = "leave the panel keys" })
end)

hl.define_submap("overview", function()
    hl.bind(mod .. " + Tab", quickshell_call("overview", "next"), { repeating = true, description = "next window" })
    hl.bind(
        mod .. " + SHIFT + Tab",
        quickshell_call("overview", "prev"),
        { repeating = true, description = "previous window" }
    )
    hl.bind(mod .. " + Return", quickshell_call("overview", "commit"), { description = "go to the selected window" })
    hl.bind(
        "Escape",
        hl.dsp.exec_cmd(
            "quickshell ipc -p ~/.config/quickshell call overview close; "
                .. "hyprctl dispatch 'hl.dsp.submap(\"reset\")'"
        ),
        { description = "close the overview" }
    )
end)
