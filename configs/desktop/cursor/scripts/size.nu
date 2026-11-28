# The pointer size, apart from the module: desktop/hyprland reads it, and cursor's mod.nu imports hyprland's.

# size_px's default, for a reader whose platform leaves this module out
export const CURSOR_SIZE_PX = 30

# The size a reader's cfg.deps entry for this module names.
export def cursor-size [cursor: any]: nothing -> int { $cursor.size_px? | default $CURSOR_SIZE_PX }
