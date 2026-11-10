# syncthing's gui password and steam's launch options became recorded actions keyed in dot's state; their own stamps
# are read by nothing any more.

export def up []: nothing -> nothing {
    let state = $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state)
    rm --force ($state | path join syncthing gui-password.stamp) ($state | path join steam-launch-options.stamp)
}
