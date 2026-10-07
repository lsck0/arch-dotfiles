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

local function media_key(action)
    return hl.dsp.exec_cmd(shell_bin("media-key") .. " " .. action)
end

-- display CTM brightness, the software dimmer below the monitor's own backlight
local color_grading = "$DOTFILES/configs/desktop/color-grading/color-grading.py"

-- obs hotkeys only fire while obs is focused on wayland; obs-status.py exits after stdin eof, timeout covers obs closed
local function obs_command(cmd)
    return hl.dsp.exec_cmd("echo '{\"cmd\":\"" .. cmd .. "\"}' | timeout 5 "
        .. "$DOTFILES/configs/desktop/quickshell/plugins/bar/widgets/obs-status.py >/dev/null")
end

hl.bind(mod .. " + SHIFT + e", quickshell_toggle("powermenu"))
hl.bind(mod .. " + SHIFT + s", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"))
hl.bind(mod .. " + SHIFT + d", hl.dsp.exec_cmd(shell_bin("gpg-clip") .. " decrypt"))
hl.bind(mod .. " + SHIFT + x", hl.dsp.exec_cmd(shell_bin("gpg-clip") .. " encrypt"))
hl.bind(mod .. " + SHIFT + c", hl.dsp.exec_cmd(shell_bin("gpg-clip") .. " sign"))
hl.bind(mod .. " + SHIFT + PRINT", hl.dsp.exec_cmd(
    "grim -o \"$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name')\" - | wl-copy"))
hl.bind("CTRL + SHIFT + ALT + s", hl.dsp.exec_cmd(
    "grim -g \"$(hyprctl -j activewindow | jq -r 'select(.at and .size) | \\\"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\\\"')\" - | wl-copy"))
hl.bind(mod .. " + SHIFT + y", hl.dsp.exec_cmd("shimejictl stop"))
hl.bind(mod .. " + F9", obs_command("saveReplay"))
hl.bind(mod .. " + SHIFT + F9", obs_command("toggleReplay"))
hl.bind(mod .. " + Tab", quickshell_toggle("overview"))
-- straight d-bus into the resident ghostty service, skips the ~180ms ghostty cli start of +new-window
hl.bind(mod .. " + Return", hl.dsp.exec_cmd("gdbus call --session --dest com.mitchellh.ghostty --object-path /com/mitchellh/ghostty --method org.gtk.Actions.Activate new-window '[]' '{}'"))
hl.bind(mod .. " + a", hl.dsp.exec_cmd("firefox"))
hl.bind(mod .. " + SHIFT + a", hl.dsp.exec_cmd("qutebrowser"))
hl.bind(mod .. " + d", quickshell_toggle("appsearch"))
hl.bind(mod .. " + m", quickshell_call("discord", "toggleMute"))
hl.bind(mod .. " + e", hl.dsp.exec_cmd("dolphin"))
hl.bind(mod .. " + n", hl.dsp.exec_cmd("neovide"))
hl.bind(mod .. " + p", hl.dsp.exec_cmd("hyprpicker | tr -d '\\n' | wl-copy"))
hl.bind(mod .. " + t", hl.dsp.exec_cmd("$DOTFILES/scripts/toggles/menu.sh"))
hl.bind(mod .. " + SHIFT + t", hl.dsp.exec_cmd("missioncenter"))
hl.bind(mod .. " + w", hl.dsp.exec_cmd(shell_bin("wallpaper-picker")))
hl.bind(mod .. " + y", hl.dsp.exec_cmd("spawn-shimeji"))
-- boomer.sh stops hyprland warping the cursor to monitor 0
hl.bind(mod .. " + x", hl.dsp.exec_cmd("$DOTFILES/configs/desktop/hyprland/boomer.sh"))
-- focused-monitor-only backup; the monitor-0 window rule misplaces it
-- hl.bind(mod .. " + SHIFT + x", hl.dsp.exec_cmd(
--     "grim -t ppm -o \"$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name')\" - | wayland-boomer --monitor-scaling \"$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .scale' | head -n1)\""))

hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + space", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + s", hl.dsp.focus({ last = true }))
hl.bind(mod .. " + f", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mod .. " + v", quickshell_toggle("clipboard"))

hl.bind(mod .. " + g", hl.dsp.layout("togglesplit"))

hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"))
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"))
hl.bind("XF86AudioMedia", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioStop", hl.dsp.exec_cmd("playerctl stop"), { locked = true })
hl.bind("XF86AudioRaiseVolume", media_key("volume-up"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", media_key("volume-down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", media_key("volume-mute"), { locked = true })
hl.bind("XF86AudioMicMute", media_key("mic-mute"), { locked = true })

hl.bind("XF86MonBrightnessUp", media_key("brightness-up"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", media_key("brightness-down"), { locked = true, repeating = true })
hl.bind("SHIFT + XF86MonBrightnessUp", hl.dsp.exec_cmd(color_grading .. " set brightness +5"),
    { locked = true, repeating = true })
hl.bind("SHIFT + XF86MonBrightnessDown", hl.dsp.exec_cmd(color_grading .. " set brightness -5"),
    { locked = true, repeating = true })

hl.bind("XF86KbdBrightnessUp", media_key("kbd-backlight-up"), { locked = true })
hl.bind("XF86KbdBrightnessDown", media_key("kbd-backlight-down"), { locked = true })
hl.bind("XF86KbdLightOnOff", media_key("kbd-backlight-toggle"), { locked = true })
hl.bind(mod .. " + SHIFT + b", media_key("kbd-backlight-toggle"), { locked = true })

-- agent-guard can inhibit the lid switch, then closing the lid undocked would neither suspend nor lock
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd(
    "loginctl show-session -p BlockInhibited --value | grep -qw handle-lid-switch"
    .. " && loginctl show-session -p Docked --value | grep -qx no && loginctl lock-session"), { locked = true })

local DIRECTIONS = {
    { keys = { "h", "Left" }, focus = "left", move = "l" },
    { keys = { "l", "Right" }, focus = "right", move = "r" },
    { keys = { "k", "Up" }, focus = "up", move = "u" },
    { keys = { "j", "Down" }, focus = "down", move = "d" },
}
for _, direction in ipairs(DIRECTIONS) do
    for _, key in ipairs(direction.keys) do
        hl.bind(mod .. " + " .. key, hl.dsp.focus({ direction = direction.focus }))
        hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = direction.move }))
        hl.bind(mod .. " + CTRL + " .. key, hl.dsp.window.move({ into_or_create_group = direction.move }))
    end
end

hl.bind(mod .. " + CTRL + w", hl.dsp.group.toggle())
hl.bind(mod .. " + c", hl.dsp.group.next())

for workspace = 1, 10 do
    local key = tostring(workspace % 10)
    hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = workspace }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace }))
end

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

local RESIZE_STEP = 30
local RESIZE = {
    { keys = { "l", "Right" }, x = RESIZE_STEP, y = 0 },
    { keys = { "h", "Left" }, x = -RESIZE_STEP, y = 0 },
    { keys = { "k", "Up" }, x = 0, y = -RESIZE_STEP },
    { keys = { "j", "Down" }, x = 0, y = RESIZE_STEP },
}
hl.bind(mod .. " + R", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    for _, step in ipairs(RESIZE) do
        for _, key in ipairs(step.keys) do
            hl.bind(key, hl.dsp.window.resize({ x = step.x, y = step.y, relative = true }), { repeating = true })
        end
    end

    hl.bind(mod .. " + R", hl.dsp.submap("reset"))
    hl.bind("Escape", hl.dsp.submap("reset"))
end)

