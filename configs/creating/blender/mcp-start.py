# from a timer: add-on operators and the window exist only once startup is done
import bpy


def bridge_start():
    bpy.ops.blmcp.server_start()


bpy.app.timers.register(bridge_start, first_interval=1.0)
