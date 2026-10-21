#!/usr/bin/env -S nu --no-config-file
# blender with the mcp bridge open from the start; plain blender keeps it closed

const START = path self | path expand | path dirname | path join mcp-start.py

def --wrapped main [...args: string]: nothing -> nothing {
    exec blender ...$args --python $START
}
