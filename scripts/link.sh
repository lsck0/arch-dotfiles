#!/usr/bin/env bash

set -ex

ls -1 *.sh | grep -v "link.sh" | xargs -I {} sh -c 'sudo ln -sf $PWD/{} /usr/local/bin/$(basename "{}" .sh)'
ls -1 *.py | xargs -I {} sh -c 'sudo ln -sf $PWD/{} /usr/local/bin/$(basename "{}" .py)'
