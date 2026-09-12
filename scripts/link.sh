#!/usr/bin/env bash
# Links every script in scripts/ onto PATH (/usr/local/bin). These are
# user-facing CLI tools (backup-obs.sh, git-sync.sh, hms.sh, ...), not configs
# tied to a specific program being installed — they should always be on PATH.
set -ex

ls -1 *.sh | grep -v "link.sh" | xargs -I {} sh -c 'sudo ln -sf $PWD/{} /usr/local/bin/$(basename "{}" .sh)'
ls -1 *.py | xargs -I {} sh -c 'sudo ln -sf $PWD/{} /usr/local/bin/$(basename "{}" .py)'
