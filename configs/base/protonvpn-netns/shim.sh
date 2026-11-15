#!/bin/sh
# managed by arch-dotfiles/protonvpn-netns: shadows /usr/bin/<name> so it only runs inside the vpn namespace. sh, not
# nu: a nu script evaluates and requotes its --flag=value arguments, "$@" passes them on untouched.
set -eu

NS=protonvpn
RUN=/usr/local/lib/protonvpn-netns/run

name=${0##*/}
if [ "$name" = mpv-stream ]; then
    set -- /usr/bin/mpv --ytdl=yes "$@"
else
    set -- "/usr/bin/$name" "$@"
fi
# already inside (ani-cli's yt-dlp): a second sudo would fail
if [ "$(ip netns identify 2> /dev/null)" = "$NS" ]; then
    exec "$@"
fi
# the namespace entry is a wheel-only sudo rule: say so instead of sudo's "a password is required"
case " $(id -nG) " in
    *" wheel "*) ;;
    *)
        printf '%s runs only inside the vpn namespace, which needs a wheel login; ask an admin\n' "$name" >&2
        exit 1
        ;;
esac
exec sudo -n "$RUN" "$@"
