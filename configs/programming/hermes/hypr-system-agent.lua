-- programming/hermes' system agent in hyprland, a drop-in (desktop/hyprland loads ~/.config/hypr/dropins/*.lua): a
-- dropdown attached to its tmux session on its own special workspace; hiding it only detaches, the agent keeps working
local mod = "SUPER"
local terminal = "ghostty --gtk-single-instance=false --class=system-agent -e tmux -L system-agent attach -t agent"

hl.window_rule({
    match = { class = "^system-agent$" },
    workspace = "special:agent silent",
    float = true,
    center = true,
    size = "monitor_w*0.6 monitor_h*0.7",
})

hl.bind(mod .. " + grave", function()
    if #hl.get_windows({ class = "system-agent" }) == 0 then
        hl.exec_cmd("uwsm app -- " .. terminal)
    end
    hl.dispatch(hl.dsp.workspace.toggle_special("agent"))
end, { description = "system agent: show or hide its window" })

-- ctrl+space is its record key: sent to the pane it works with the window hidden; it answers aloud
hl.bind(
    mod .. " + ALT + a",
    hl.dsp.exec_cmd("tmux -L system-agent send-keys -t agent C-Space"),
    { description = "system agent: talk (start or stop recording)" }
)
