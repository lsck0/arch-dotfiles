#!/usr/bin/env bash

SPOTIFY_DIR=/opt/spotify

# spicetify patches the client in place: wheel gets write access instead of one user owning it; the hook regrants it after upgrades
install -Dm644 spotify-group-write.hook /etc/pacman.d/hooks/spotify-group-write.hook
[[ -d "$SPOTIFY_DIR" ]] || exit 0
chgrp -R wheel "$SPOTIFY_DIR"
chmod -R g+w "$SPOTIFY_DIR"
