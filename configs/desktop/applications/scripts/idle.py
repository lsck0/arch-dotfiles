#!/usr/bin/python3
# IDLE converts tk's pixel fonts to points once tk scaling passes HiDPI, so raising the scaling scales all of its ui.
import idlelib.util
import os
from idlelib.pyshell import main

fix_scaling = idlelib.util.fix_scaling


def fix_scaling_xwayland(root):
    scale = float(os.environ.get("GDK_SCALE", "1"))
    root.tk.call("tk", "scaling", float(root.tk.call("tk", "scaling")) * scale)
    fix_scaling(root)


idlelib.util.fix_scaling = fix_scaling_xwayland

if __name__ == "__main__":
    main()
