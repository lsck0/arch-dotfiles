#!/bin/sh
# blender with the mcp bridge open from the start; plain blender keeps it closed. sh, not nu: a nu script evaluates and
# requotes its --flag=value arguments, "$@" passes them on untouched.
set -eu

# linked into ~/.local/bin: mcp-start.py sits beside the file itself
here=$(dirname "$(readlink -f "$0")")
exec blender "$@" --python "$here/mcp-start.py"
