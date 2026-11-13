local platform = require("platform")

-- one app of the platform's autostart list, through uwsm like every launch; its own process's first window takes the
-- workspace and float rules
local function autostart_launch(entry)
    local rules = {}
    if entry.workspace then
        rules.workspace = tostring(entry.workspace) .. " silent"
    end
    if entry.float then
        rules.float = true
        rules.center = true
    end
    hl.exec_cmd("uwsm-app -- " .. entry.cmd, next(rules) and rules or nil)
end

-- The entries still waiting on their after window, as indexes into platform.autostart, one per line. A file under this
-- instance's runtime dir, since plugins.nu's `hyprctl reload` at login rebuilds the lua state and with it any
-- subscription made in hyprland.start; each load picks the list up again.
local function pending_path()
    local runtime, instance = os.getenv("XDG_RUNTIME_DIR"), os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
    if not runtime or not instance then
        return nil
    end
    return runtime .. "/hypr/" .. instance .. "/autostart-pending"
end

local function pending_read()
    local path, out = pending_path(), {}
    local f = path and io.open(path, "r")
    if not f then
        return out
    end
    for line in f:lines() do
        local i = tonumber(line)
        if i and platform.autostart[i] then
            table.insert(out, i)
        end
    end
    f:close()
    return out
end

local function pending_write(indexes)
    local path = pending_path()
    if not path then
        return
    end
    if #indexes == 0 then
        os.remove(path)
        return
    end
    local f = io.open(path, "w")
    if f then
        f:write(table.concat(indexes, "\n"), "\n")
        f:close()
    end
end

-- an entry with after starts once a window of that class is open, so a shared workspace fills in a fixed order; one
-- already open (it mapped during a reload) counts
local function pending_watch()
    local waiting = pending_read()
    if #waiting == 0 then
        return
    end
    -- read again each time: should a reload keep the old state, a second subscription finds the entry gone
    local function release(class)
        local kept = {}
        for _, i in ipairs(pending_read()) do
            if platform.autostart[i].after == class then
                autostart_launch(platform.autostart[i])
            else
                table.insert(kept, i)
            end
        end
        waiting = kept
        pending_write(waiting)
    end
    for _, window in ipairs(hl.get_windows()) do
        release(window.class)
    end
    if #waiting == 0 then
        return
    end
    local subscription
    subscription = hl.on("window.open", function(window)
        release(window.class)
        if #waiting == 0 and subscription then
            subscription:remove()
        end
    end)
end

local function autostart()
    local waiting = {}
    for i, entry in ipairs(platform.autostart) do
        if entry.after then
            table.insert(waiting, i)
        else
            autostart_launch(entry)
        end
    end
    pending_write(waiting)
    pending_watch()
end

-- a reload after start (plugins.nu at login) resumes what still waits
pending_watch()

hl.on("hyprland.start", function()
    -- the hl.env scales too, so quickshell.service and every app it launches see what the compositor's children see
    hl.exec_cmd("uwsm finalize GDK_SCALE")

    -- quickshell's unit waits for the finalize above
    hl.exec_cmd("systemctl --user start quickshell.service")
    -- a copy outlives its app; Qt image copies (they offer image/jxr, whose encoder segfaults) are left alone. -f
    -- needs every offered type to match, so it lists the vendor prefixes too (chromium/ from every Electron app,
    -- x-special/ from file managers)
    hl.exec_cmd(
        "uwsm-app -s b -- wl-clip-persist --clipboard regular -f '^((text|application|chromium|x-special)/.*|[^/]*|image/(png|jpeg|gif|webp|bmp|tiff|avif|svg\\+xml))$'"
    )

    -- the shell expands $DOTFILES (an unset getenv would abort this hook); plugins.nu builds and loads the plugins
    hl.exec_cmd("uwsm-app -s b -- $DOTFILES/configs/desktop/hyprland/plugins.nu")
    hl.exec_cmd("uwsm-app -s b -- $DOTFILES/configs/desktop/shimoji/packs.nu")
    -- a session started docked with the lid already closed
    hl.exec_cmd("$DOTFILES/configs/desktop/hyprland/lid.nu")

    -- root GUI apps under Xwayland (gparted through pkexec) need the display
    hl.exec_cmd("xhost +SI:localuser:root")
    -- nsxiv reads its colours only from the X server's resources, which start empty each session; the file is
    -- desktop/nsxiv's theme output, absent without nsxiv or before the first theme
    hl.exec_cmd(
        'f="${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors-nsxiv.Xresources"; [ -f "$f" ] && xrdb -nocpp -merge "$f"'
    )
    autostart()
    -- in the monitors' own firmware: a monitor reset or a new one would undo it
    if platform.monitor_speaker_volume then
        hl.exec_cmd(
            "for d in $(ddcutil detect --terse 2>/dev/null | sed -n 's/^Display \\([0-9]*\\)$/\\1/p'); do ddcutil --display \"$d\" setvcp 62 "
                .. platform.monitor_speaker_volume
                .. "; done"
        )
    end
    if platform.kbd_backlight then
        hl.exec_cmd("brightnessctl --device=" .. platform.kbd_backlight .. " set 2")
    end
end)
