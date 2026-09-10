#!/usr/bin/env bash
# Wires `use devenv` support into direnv globally, by generating
# ~/.config/direnv/direnvrc from `devenv direnvrc` (devenv's own canonical
# output — https://devenv.sh/integrations/direnv/). Without this, any
# .envrc saying `use devenv` (e.g. l-agent-task-db's scaffold.sh output)
# fails with "use_devenv: command not found" the moment direnv tries to
# load it — there's no other place this function comes from.
#
# Guarded on devenv actually being installed, and regenerated every run so
# a devenv upgrade's direnvrc changes get picked up — this is generated
# output, never hand-edited, so overwriting it is always safe.
set -ex

if command -v devenv >/dev/null 2>&1; then
  mkdir -p "${HOME}/.config/direnv"
  devenv direnvrc > "${HOME}/.config/direnv/direnvrc"
fi
