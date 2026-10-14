# mod.nu's addon-install runs this in `blender -b` over the person's own preferences: the mcp add-on enabled, its bridge
# pinned to loopback and never auto-started, and online access on, without which the add-on refuses to open its socket.
# the bridge runs any python sent to it, so it opens only on an explicit start (blender-mcp-bridge, or the add-on's
# preferences). saved only when one of these actually changed, so a run over a set-up blender leaves userpref.blend
# alone
import addon_utils
import bpy

ADDON = "bl_ext.user_default.mcp"
HOST = "127.0.0.1"
PORT = 9876

prefs = bpy.context.preferences
changed = False

_, enabled = addon_utils.check(ADDON)
if not enabled:
    addon_utils.enable(ADDON, default_set=True, persistent=True, handle_error=None)
    changed = True
assert addon_utils.check(ADDON)[1], "blender: the mcp add-on would not enable"

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
