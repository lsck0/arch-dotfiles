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
    hl.exec_cmd("uwsm app -- " .. entry.cmd, next(rules) and rules or nil)
end

local function autostart()
    local waiting = {}
    for _, entry in ipairs(platform.autostart or {}) do
        if entry.after then
            table.insert(waiting, entry)
        else
            autostart_launch(entry)
        end
    end
    if #waiting == 0 then
        return
    end
    -- an entry with after starts once a window of that class opens, so a shared workspace fills in a fixed order
    local subscription
    subscription = hl.on("window.open", function(window)
        for i = #waiting, 1, -1 do
            if window.class == waiting[i].after then
                autostart_launch(table.remove(waiting, i))
            end
        end
        if #waiting == 0 and subscription then
            subscription:remove()
        end
    end)
end

hl.on("hyprland.start", function()
    -- the hl.env scales too, so quickshell.service and every app it launches see what the compositor's children see
    hl.exec_cmd("uwsm finalize GDK_SCALE")

    -- quickshell's unit waits for the finalize above
    hl.exec_cmd("systemctl --user start quickshell.service")
    -- a copy outlives its app; Qt image copies (they offer image/jxr, whose encoder segfaults) are left alone. -f
    -- needs every offered type to match, so it lists the vendor prefixes too (chromium/ from every Electron app,
    -- x-special/ from file managers)
    hl.exec_cmd(
        "uwsm app -s b -- wl-clip-persist --clipboard regular -f '^((text|application|chromium|x-special)/.*|[^/]*|image/(png|jpeg|gif|webp|bmp|tiff|avif|svg\\+xml))$'"
    )

    -- the shell expands $DOTFILES (an unset getenv would abort this hook); plugins.nu builds and loads the plugins
    hl.exec_cmd("uwsm app -s b -- $DOTFILES/configs/desktop/hyprland/plugins.nu")
    hl.exec_cmd("uwsm app -s b -- $DOTFILES/configs/desktop/shimoji/packs.nu")
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
    local backlight = platform.kbd_backlight
    if backlight then
        hl.exec_cmd("brightnessctl --device=" .. backlight .. " set 2")
    end
end)
