hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm finalize")

    -- long-running apps -> scoped systemd units
    hl.exec_cmd("uwsm app -- awww-daemon")
    hl.exec_cmd("uwsm app -- copyq --start-server")
    hl.exec_cmd("uwsm app -- hypridle")
    hl.exec_cmd("uwsm app -- mako")
    hl.exec_cmd("uwsm app -- waybar")

    -- oneshots, leave bare
    hl.exec_cmd("hyprpm reload")
    hl.exec_cmd("xhost + local:")
    hl.exec_cmd("xhost +SI:localuser:root")

    -- has to be in that order
    hl.exec_cmd("uwsm app -- elephant")
    hl.exec_cmd("uwsm app -- walker --gapplication-service")
end)
