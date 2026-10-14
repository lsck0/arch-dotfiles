# blender-mcp-bridge runs this at startup: the add-on's own start operator, from a timer since add-on operators and the
# window are only there once startup is done
import bpy


def bridge_start():
    bpy.ops.blmcp.server_start()


bpy.app.timers.register(bridge_start, first_interval=1.0)
