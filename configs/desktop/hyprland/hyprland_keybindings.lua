local mod = "SUPER"
-- workspaces 1 to 10 on keys 1 to 0, the WORKSPACE_COUNT that mod.nu splits over the outputs
local WORKSPACE_COUNT = 10

local function shell_bin(name)
    return "~/.local/bin/" .. name
end

local function hypr_script(name)
    return "$DOTFILES/configs/desktop/hyprland/" .. name
end

local function quickshell_cmd(target, fn)
    return "quickshell ipc -p ~/.config/quickshell call " .. target .. " " .. fn
end

local function quickshell_call(target, fn)
    return hl.dsp.exec_cmd(quickshell_cmd(target, fn))
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
for _, keys in ipairs({ "Print", mod .. " + SHIFT + s" }) do
    hl.bind(
        keys,
        hl.dsp.exec_cmd(hypr_script("screenshot.nu") .. " region"),
        { description = "screenshot a region to ~/pictures/screenshots and the clipboard" }
    )
end
hl.bind(
    "SHIFT + Print",
    hl.dsp.exec_cmd(hypr_script("screenshot.nu") .. " output"),
    { description = "screenshot the focused monitor to ~/pictures/screenshots and the clipboard" }
)
hl.bind(
    mod .. " + Print",
    hl.dsp.exec_cmd(hypr_script("screenshot.nu") .. " window"),
    { description = "screenshot the active window to ~/pictures/screenshots and the clipboard" }
)
hl.bind(
    mod .. " + ALT + Print",
    hl.dsp.exec_cmd(hypr_script("record.nu")),
    { description = "start or stop a screen recording into ~/videos/recordings" }
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
        "cmd=$(bash -c 'compgen -c' | sort -u | " .. hypr_script("picker.nu") .. ' -p run) && uwsm-app -- sh -c "$cmd"'
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
-- the notes are plain markdown in ~/sync/notes: nvim opens on the capture inbox with the folder as its cwd
hl.bind(
    mod .. " + ALT + n",
    app(
        "kitty --class notes sh -c "
            .. '\'d="$HOME/sync/notes"; mkdir -p "$d"; cd "$d"; exec "${EDITOR:-nvim}" inbox.md\''
    ),
    { description = "notes folder in the editor, on the inbox" }
)
hl.bind(
    mod .. " + i",
    quickshell_call("appsearch", "openWith '+ '"),
    { description = "quick capture: task (! reminder, # note)" }
)
hl.bind(mod .. " + SHIFT + i", quickshell_call("appsearch", "openWith '! '"), { description = "quick reminder" })
hl.bind(mod .. " + o", quickshell_toggle("tasks"), { description = "tasks and notes panel" })
hl.bind(mod .. " + ALT + v", helper(shell_bin("dictate")), { description = "dictation: speak, press again to type it" })

hl.bind(mod .. " + comma", quickshell_toggle("settings"), { description = "settings window" })
hl.bind(mod .. " + p", hl.dsp.exec_cmd("hyprpicker -a -n"), { description = "pick a screen color to the clipboard" })
hl.bind(mod .. " + t", quickshell_call("shell", "summon panel.reminders {}"), { description = "timer and pomodoro" })
hl.bind(mod .. " + SHIFT + t", app("missioncenter"), { description = "system monitor (mission center)" })
hl.bind(mod .. " + CTRL + w", helper(shell_bin("wallpaper-picker")), { description = "wallpaper picker" })
hl.bind(mod .. " + SHIFT + w", helper(shell_bin("wallpaper-picker") .. " --themes"), { description = "theme picker" })
hl.bind(mod .. " + y", helper(shell_bin("spawn-shimeji")), { description = "spawn a desktop mascot" })
hl.bind(mod .. " + x", app(hypr_script("boomer.nu")), { description = "magnifier (boomer)" })

hl.bind(mod .. " + q", hl.dsp.exec_cmd(hypr_script("window-close.nu")), {
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

-- locked: they work on the lock screen too
local LOCKED_KEYS = {
    { "XF86AudioPlay", media_key("play-pause"), "play or pause media" },
    { "XF86AudioMedia", media_key("play-pause"), "play or pause media" },
    { "XF86AudioPrev", media_key("previous"), "previous track" },
    { "XF86AudioNext", media_key("next"), "next track" },
    { "XF86AudioStop", media_key("stop"), "stop media" },
    { "XF86AudioRaiseVolume", media_key("volume-up"), "volume up", true },
    { "XF86AudioLowerVolume", media_key("volume-down"), "volume down", true },
    { "XF86AudioMute", media_key("volume-mute"), "mute the output" },
    { "XF86AudioMicMute", media_key("mic-mute"), "mute the microphone" },
    { "XF86MonBrightnessUp", media_key("brightness-up"), "brightness up", true },
    { "XF86MonBrightnessDown", media_key("brightness-down"), "brightness down", true },
    {
        "SHIFT + XF86MonBrightnessUp",
        media_key("software-brightness-up"),
        "software brightness up (color grading)",
        true,
    },
    {
        "SHIFT + XF86MonBrightnessDown",
        media_key("software-brightness-down"),
        "software brightness down (color grading)",
        true,
    },
    { "XF86KbdBrightnessUp", media_key("kbd-backlight-up"), "keyboard backlight up" },
    { "XF86KbdBrightnessDown", media_key("kbd-backlight-down"), "keyboard backlight down" },
    { "XF86KbdLightOnOff", media_key("kbd-backlight-toggle"), "keyboard backlight on or off" },
    { mod .. " + SHIFT + b", media_key("kbd-backlight-toggle"), "keyboard backlight on or off" },
}
for _, key in ipairs(LOCKED_KEYS) do
    hl.bind(key[1], key[2], { locked = true, repeating = key[4], description = key[3] })
end

-- agent-guard can inhibit the lid switch; then an undocked close locks instead of suspending
hl.bind(
    "switch:on:Lid Switch",
    hl.dsp.exec_cmd(
        hypr_script("lid.nu")
            .. " closed; loginctl show-session -p BlockInhibited --value | grep -qw handle-lid-switch"
            .. " && loginctl show-session -p Docked --value | grep -qx no && loginctl lock-session"
    ),
    { locked = true, description = "lid closed: internal panel off when docked, lock when inhibited and undocked" }
)
hl.bind(
    "switch:off:Lid Switch",
    hl.dsp.exec_cmd(hypr_script("lid.nu") .. " open"),
    { locked = true, description = "lid opened: internal panel back on" }
)

local DIRECTIONS = {
    { keys = { "h", "Left" }, focus = "left", move = "l" },
    { keys = { "l", "Right" }, focus = "right", move = "r" },
    { keys = { "k", "Up" }, focus = "up", move = "u" },
    { keys = { "j", "Down" }, focus = "down", move = "d" },
}
hl.config({ binds = { movefocus_cycles_groupfirst = true } })

-- i3 tabs: left/right reorder within the group, then leave it at its edge
local function move_through_tabs(direction)
    local window = hl.get_active_window()
    local group = window and window.group
    if group and group.size > 1 then
        if direction.move == "l" and group.current_index > 1 then
            return hl.dsp.group.move_window({ forward = false })
        elseif direction.move == "r" and group.current_index < group.size then
            return hl.dsp.group.move_window({ forward = true })
        end
    end
    return hl.dsp.window.move({ direction = direction.move, group_aware = true })
end
for _, direction in ipairs(DIRECTIONS) do
    for _, key in ipairs(direction.keys) do
        hl.bind(
            mod .. " + " .. key,
            hl.dsp.focus({ direction = direction.focus }),
            { description = "focus the window " .. direction.focus }
        )
        hl.bind(mod .. " + SHIFT + " .. key, function()
            hl.dispatch(move_through_tabs(direction))
        end, {
            description = "move the window "
                .. direction.focus
                .. ((direction.move == "l" or direction.move == "r") and ", reordering its tab first" or ""),
        })
        hl.bind(
            mod .. " + CTRL + " .. key,
            hl.dsp.window.move({ into_or_create_group = direction.move }),
            { description = "tab the window with its neighbour " .. direction.focus }
        )
    end
end

hl.bind(mod .. " + w", hl.dsp.group.toggle(), { description = "tab or untab the window (i3 tabbed)" })
hl.bind(mod .. " + c", hl.dsp.group.next(), { description = "next tab" })
hl.bind(mod .. " + SHIFT + c", hl.dsp.group.prev(), { description = "previous tab" })

for workspace = 1, WORKSPACE_COUNT do
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
hl.bind(mod .. " + r", hl.dsp.submap("resize"), { description = "resize mode" })
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

    hl.bind(mod .. " + r", hl.dsp.submap("reset"), { description = "leave resize mode" })
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
        hl.dsp.exec_cmd(quickshell_cmd("overview", "close") .. "; hyprctl dispatch 'hl.dsp.submap(\"reset\")'"),
        { description = "close the overview" }
    )
end)
