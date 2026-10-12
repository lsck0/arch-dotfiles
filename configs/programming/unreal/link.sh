#!/usr/bin/env bash

# a ~60 GB engine is a desktop workload
[[ $FORM_FACTOR == desktop ]] || exit 0

# the editor launcher and claude's link to the mcp server it starts, for whichever engine is installed
link_commands unreal-editor.sh
# .uproject's type, for the desktop entry and mimeapps.list
mime_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/mime"
file_update uproject.xml "$mime_dir/packages/uproject.xml" && update-mime-database "$mime_dir"
json_update "${HOME}/.claude.json" '.mcpServers["unreal-mcp"] = {type: "http", url: "http://127.0.0.1:8766/mcp"}'

# the newest zip installs here, first install or a later version, into the home: no root, never asked
./hook/unreal-install.sh
# still missing (no zip yet): arm the path unit to wait for one; the install hook retires itself once an engine is in
unreal_installed() { [[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/unreal-engine/.installed-from" ]]; }
user_hook_oneshot unreal-install unreal_installed --mkdir --watch "%h/sync/vendor"
# bridge and fab again after a new plugin zip, without a new engine
link_commands unreal-install-plugins.sh
