#!/usr/bin/env bash

PAM_ENV=/etc/security/pam_env.conf

# every session gets the base dirs; zshrc sets GOPATH only interactively, and mason's go would create ~/go
for line in "XDG_CONFIG_HOME DEFAULT=@{HOME}/.config" "XDG_CACHE_HOME  DEFAULT=@{HOME}/.cache" \
    "XDG_DATA_HOME   DEFAULT=@{HOME}/.local/share" "XDG_STATE_HOME  DEFAULT=@{HOME}/.local/state" \
    "GOPATH          DEFAULT=@{HOME}/.go"; do
    grep -qF "$line" "$PAM_ENV" || echo "$line" >>"$PAM_ENV"
done
