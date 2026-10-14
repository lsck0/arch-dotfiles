#!/usr/bin/env -S nu --no-config-file
# blender with the mcp bridge open from the start, for a session claude drives; plain blender keeps it closed. also the
# "Blender with MCP bridge" action of blender's launcher entry. usage: blender-mcp-bridge [file.blend]

const START = path self | path expand | path dirname | path join mcp-start.py

def --wrapped main [...args: string]: nothing -> nothing {
    exec blender ...$args --python $START
}
