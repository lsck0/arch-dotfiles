#!/bin/env bash

set -ex

ls -1 *.sh | grep -v "link.sh" | xargs -I {} sh -c 'sudo ln -sf $PWD/{} /usr/local/bin/$(basename "{}" .sh)'
