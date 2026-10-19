hl.env("HYPRCURSOR_SIZE", "30")
hl.env("HYPRCURSOR_THEME", "rose-pine-hyprcursor")
hl.env("XCURSOR_SIZE", "30")
hl.env("XCURSOR_THEME", "BreezeX-RosePine-Linux")

-- hyprland 0.56.2 asserts in CHyprOpenGLImpl::beginSimple on hardware cursors when a client churns cursor shapes
hl.config({ cursor = { no_hardware_cursors = 1 } })
