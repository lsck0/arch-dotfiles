import os

import addon_utils
import bpy

ADDON = "bl_ext.user_default.mcp"
HOST = os.environ["BLENDER_MCP_HOST"]
PORT = int(os.environ["BLENDER_MCP_PORT"])

prefs = bpy.context.preferences
changed = False

_, enabled = addon_utils.check(ADDON)
if not enabled:
    addon_utils.enable(ADDON, default_set=True, persistent=True, handle_error=None)
    changed = True
assert addon_utils.check(ADDON)[1], "blender: the mcp add-on would not enable"

# the mcp add-on refuses to start without global online access (its startup checks bpy.app.online_access)
if not prefs.system.use_online_access:
    prefs.system.use_online_access = True
    changed = True

addon = prefs.addons[ADDON].preferences
for name, value in (("host", HOST), ("port", PORT), ("use_autostart", False)):
    if getattr(addon, name) != value:
        setattr(addon, name, value)
        changed = True

if changed:
    prefs.is_dirty = True
    bpy.ops.wm.save_userpref()
    print("blender: mcp add-on preferences saved")
