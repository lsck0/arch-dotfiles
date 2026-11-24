import bpy


def bridge_start():
    bpy.ops.blmcp.server_start()


bpy.app.timers.register(bridge_start, first_interval=1.0)
